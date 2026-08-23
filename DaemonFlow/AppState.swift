//
//  AppState.swift
//  DaemonFlow
//

import Combine
import Foundation
import os

@MainActor
final class AppState: ObservableObject {
    let hotkeyManager: HotkeyManager
    let modelDownloadManager: ModelDownloadManager
    let audioCaptureManager: AudioCaptureManager
    let cleanupModelManager: CleanupModelManager
    let vocabularyStore = VocabularyStore()
    let hudSettings = HUDSettingsStore()
    let promptStore = PromptStore()
    let hudModel = HUDModel()

    private let transcriber = WhisperTranscriber()
    private let parakeetTranscriber = ParakeetTranscriber()
    private let cleanupEngine: LLMCleanupEngine
    private let textInjector = TextInjector()
    private let selectionRefiner = SelectionRefiner()
    private let transcriptStore = TranscriptStore()
    private var hudController: RecordingHUDController?

    /// Set while a held ⌥1 is capturing a spoken instruction. The
    /// selection is grabbed as soon as the hold begins (in parallel with
    /// recording) so the paste at the end has something to replace even if
    /// the user changes focus while speaking.
    private var pendingSelectionCapture: Task<String?, Never>?

    /// Drives root view routing: true once Accessibility (hotkey + paste
    /// injection) and Microphone are both granted. Gates everything below —
    /// there is no point offering model downloads before the app can
    /// actually record or inject anything.
    @Published private(set) var hasRequiredPermissions: Bool

    /// Drives root view routing: true once both a transcription model
    /// (Whisper or Parakeet) and a cleanup model have been selected
    /// (two-step onboarding complete).
    @Published private(set) var hasCompletedOnboarding: Bool

    /// Sheet triggers for the standalone model pickers and cleanup lab.
    @Published var isPresentingModelPicker = false
    @Published var isPresentingCleanupPicker = false
    @Published var isPresentingCleanupLab = false
    @Published var isPresentingVocabulary = false
    @Published var isPresentingHUDAppearance = false
    @Published var isPresentingPrompts = false

    /// ⌥1 refine lifecycle: drives the HUD's live meter while the user
    /// dictates an instruction, the shimmering "Refining" label while the
    /// edit is in flight, and the brief "Done" confirmation after the paste.
    enum RefinePhase: Equatable {
        case idle
        /// ⌥1 is being held — capturing the spoken instruction.
        case listening
        case refining
        case done
    }

    @Published private(set) var isTranscribing = false
    @Published private(set) var refinePhase: RefinePhase = .idle
    @Published private(set) var lastTranscript = ""

    /// Raw, uncleaned transcription of the dictation currently in
    /// progress, refreshed every livePreviewInterval while Fn is held.
    /// Feedback only — the pipeline still transcribes the complete
    /// recording (and cleans it) on release.
    @Published private(set) var liveTranscript = ""
    @Published private(set) var transcriptHistory: [TranscriptEntry] = []
    @Published private(set) var transcriptionError: String?

    /// Below ~0.5s of audio (at 16kHz) is treated as an accidental Fn tap:
    /// no transcription, no injection.
    private static let minimumSampleCount = 8000

    /// A spoken refine instruction can legitimately be very short ("shorter",
    /// "formal"), so the floor here is lower than for dictation — but still
    /// non-zero, so a hold the user aborted without speaking degrades to a
    /// plain refine rather than feeding noise to the model.
    private static let minimumInstructionSampleCount = 4000

    /// How often the live preview re-transcribes what has been captured so
    /// far. Each pass re-runs the model over the whole buffer, so this is
    /// a floor rather than a fixed cadence: a pass that takes longer than
    /// the interval simply pushes the next one out.
    private static let livePreviewInterval = Duration.milliseconds(700)

    /// Under ~0.75s there isn't enough speech for a preview worth showing,
    /// and short buffers are exactly where Whisper invents filler.
    private static let minimumLivePreviewSampleCount = 12000

    /// The HUD shows at most two lines; keeping the tail well under that
    /// avoids relying on truncation for the common case.
    private static let livePreviewCharacterLimit = 90

    /// Cancelled the moment Fn is released, so a partial that lands after
    /// the fact can't overwrite the HUD on its way out.
    private var livePreviewTask: Task<Void, Never>?

    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "pipeline")

    private var cancellables = Set<AnyCancellable>()

    init() {
        let hotkeyManager = HotkeyManager()
        let modelDownloadManager = ModelDownloadManager()
        let cleanupEngine = LLMCleanupEngine()
        let cleanupModelManager = CleanupModelManager(engine: cleanupEngine)
        self.hotkeyManager = hotkeyManager
        self.modelDownloadManager = modelDownloadManager
        self.cleanupEngine = cleanupEngine
        self.cleanupModelManager = cleanupModelManager
        let audioCaptureManager = AudioCaptureManager()
        self.audioCaptureManager = audioCaptureManager
        self.hasCompletedOnboarding = Self.computeOnboardingComplete(modelDownloadManager, cleanupModelManager)
        self.hasRequiredPermissions = Self.computePermissionsGranted(hotkeyManager, audioCaptureManager)
        self.transcriptHistory = transcriptStore.load()
        self.lastTranscript = transcriptHistory.first?.text ?? ""

        Publishers.CombineLatest4(
            modelDownloadManager.$selectedFileName,
            modelDownloadManager.$selectedEngine,
            modelDownloadManager.$isParakeetDownloaded,
            cleanupModelManager.$selectedHubRepoID
        )
            .sink { [weak self] _, _, _, _ in
                guard let self else { return }
                self.hasCompletedOnboarding = Self.computeOnboardingComplete(modelDownloadManager, cleanupModelManager)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            hotkeyManager.$needsAccessibilityPermission,
            hotkeyManager.$needsInputMonitoringPermission,
            audioCaptureManager.$micAuthorizationStatus
        )
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                self.hasRequiredPermissions = Self.computePermissionsGranted(hotkeyManager, audioCaptureManager)
            }
            .store(in: &cancellables)

        hotkeyManager.$isRecording
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isRecording in
                if isRecording {
                    self?.audioCaptureManager.startRecording()
                    self?.startLivePreview()
                } else {
                    self?.stopLivePreview()
                    self?.finishRecordingAndTranscribe()
                }
            }
            .store(in: &cancellables)

        hudController = RecordingHUDController(model: hudModel, audio: audioCaptureManager)

        runCleanupSelfTestIfRequested()

        hotkeyManager.refineTriggered
            .sink { [weak self] in
                self?.refineSelection()
            }
            .store(in: &cancellables)

        hotkeyManager.instructedRefineStarted
            .sink { [weak self] in
                self?.beginInstructedRefine()
            }
            .store(in: &cancellables)

        hotkeyManager.instructedRefineFinished
            .sink { [weak self] in
                self?.finishInstructedRefine()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            hotkeyManager.$isRecording,
            $isTranscribing,
            $refinePhase,
            hudSettings.$alwaysVisible
        )
            .map { isRecording, isTranscribing, refinePhase, alwaysShowHUD -> HUDState in
                if isRecording { return .recording }
                if isTranscribing { return .processing }
                switch refinePhase {
                case .listening: return .instructing
                case .refining: return .refining
                case .done: return .done
                case .idle: return alwaysShowHUD ? .idle : .hidden
                }
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [hudModel] state in
                hudModel.state = state
            }
            .store(in: &cancellables)

        $liveTranscript
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [hudModel] text in
                hudModel.liveText = text
            }
            .store(in: &cancellables)

        // The pill lives in an NSPanel, outside the SwiftUI environment
        // the settings sheet edits — so its sizes are pushed to it here.
        hudSettings.$appearance
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [hudModel] appearance in
                hudModel.appearance = appearance
            }
            .store(in: &cancellables)
    }

    /// Re-transcribes the in-progress recording on a loop so the HUD can
    /// show what is being heard while the user is still talking. Runs the
    /// same engine the final pass will use — no cleanup, no history, no
    /// injection.
    private func startLivePreview() {
        livePreviewTask?.cancel()
        liveTranscript = ""

        guard let route = currentTranscriptionRoute() else { return }

        livePreviewTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.livePreviewInterval)
                guard !Task.isCancelled, let self else { return }

                let samples = self.audioCaptureManager.snapshotSamples()
                guard samples.count >= Self.minimumLivePreviewSampleCount else { continue }

                // Shares the transcriber actor with the final pass, so at
                // most one preview can ever be in flight — and the final
                // transcription queues behind at most that one.
                guard let text = try? await self.transcribe(samples, using: route) else { continue }
                guard !Task.isCancelled else { return }

                let corrected = VocabularyCorrector.apply(text, terms: self.vocabularyStore.termStrings)
                self.liveTranscript = Self.livePreviewText(from: corrected)
            }
        }
    }

    private func stopLivePreview() {
        livePreviewTask?.cancel()
        livePreviewTask = nil
        liveTranscript = ""
    }

    /// Strips the bracketed annotations Whisper emits for non-speech
    /// (`[BLANK_AUDIO]`, `(wind blowing)`) and keeps only the tail, which
    /// is the part the user is actually saying right now.
    private static func livePreviewText(from raw: String) -> String {
        let withoutAnnotations = raw
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\([^)]*\\)", with: " ", options: .regularExpression)
        let collapsed = withoutAnnotations
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > Self.livePreviewCharacterLimit else { return collapsed }

        let tail = collapsed.suffix(Self.livePreviewCharacterLimit)
        // Start at a word boundary so the preview never opens mid-word.
        guard let spaceIndex = tail.firstIndex(of: " ") else { return "…" + tail }
        return "…" + tail[tail.index(after: spaceIndex)...]
    }

    /// `.done` is only a two-second confirmation badge, not busy state — a
    /// ⌥1 pressed during that window should start a new refine rather than
    /// be silently dropped. The previous refine's pending reset-to-idle
    /// checks for `.done` before firing, so it won't clobber the new one.
    private var canStartRefine: Bool {
        refinePhase == .idle || refinePhase == .done
    }

    /// ⌥1 tapped: capture the selection in the frontmost app, refine it
    /// with the cleanup model, and paste the result back over the
    /// selection. Best-effort — no selection or a model error just logs
    /// and leaves the user's text untouched.
    private func refineSelection() {
        guard canStartRefine else { return }
        refinePhase = .refining

        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let selected = await self.selectionRefiner.captureSelectedText() else {
                self.refinePhase = .idle
                return
            }

            await self.applyRefinement(to: selected, instruction: nil)
        }
    }

    /// ⌥1 held past the tap threshold: start capturing the spoken
    /// instruction, and grab the selection at the same time. Both are in
    /// flight while the user talks, so nothing is serialized behind the
    /// other — the selection is settled by the time they let go.
    private func beginInstructedRefine() {
        guard canStartRefine else { return }
        refinePhase = .listening

        audioCaptureManager.startRecording()
        pendingSelectionCapture = Task { [selectionRefiner] in
            await selectionRefiner.captureSelectedText()
        }
    }

    /// ⌥1 released after a hold: stop capturing, transcribe what was said,
    /// and apply it as an edit instruction to the captured selection. If
    /// nothing usable was spoken this degrades to the plain refine rather
    /// than doing nothing — the user did ask for *something*.
    private func finishInstructedRefine() {
        guard refinePhase == .listening else { return }

        let samples = audioCaptureManager.stopRecording()
        let selectionCapture = pendingSelectionCapture
        pendingSelectionCapture = nil
        refinePhase = .refining

        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let selected = await selectionCapture?.value else {
                self.logger.info("Instructed refine cancelled — nothing was selected")
                self.refinePhase = .idle
                return
            }

            let instruction = await self.transcribeInstruction(samples: samples)
            await self.applyRefinement(to: selected, instruction: instruction)
        }
    }

    /// Turns the held-⌥1 audio into an instruction string, or nil when
    /// there wasn't enough speech (or no Whisper model) to work with.
    private func transcribeInstruction(samples: [Float]) async -> String? {
        guard samples.count >= Self.minimumInstructionSampleCount else {
            logger.info("Instructed refine: only \(samples.count, privacy: .public) samples — falling back to plain refine")
            return nil
        }
        guard let route = currentTranscriptionRoute() else {
            logger.error("Instructed refine: no transcription model selected — falling back to plain refine")
            return nil
        }

        do {
            let raw = try await transcribe(samples, using: route)
            let instruction = VocabularyCorrector.apply(raw, terms: vocabularyStore.termStrings)
            logger.info("Refine instruction: \(instruction, privacy: .public)")
            return instruction
        } catch {
            logger.error("Instruction transcription failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Shared tail of both ⌥1 paths: run the model, paste over the
    /// selection, and flash the HUD confirmation.
    private func applyRefinement(to selection: String, instruction: String?) async {
        do {
            let refined = try await cleanupEngine.refine(
                selection,
                instruction: instruction,
                hubRepoID: cleanupModelManager.effectiveHubRepoID
            )
            guard !refined.isEmpty else {
                refinePhase = .idle
                return
            }
            textInjector.inject(refined)

            // Brief "Done" confirmation in the HUD, then hide.
            refinePhase = .done
            try? await Task.sleep(for: .seconds(2))
            if refinePhase == .done {
                refinePhase = .idle
            }
        } catch {
            logger.error("Refine failed: \(error.localizedDescription, privacy: .public)")
            refinePhase = .idle
        }
    }

    /// Resolves the current engine selection into something the
    /// transcription task can run with, or nil when nothing usable is
    /// selected yet.
    private func currentTranscriptionRoute() -> TranscriptionRoute? {
        switch modelDownloadManager.selectedEngine {
        case .whisper:
            guard let modelPath = modelDownloadManager.selectedModelPath() else { return nil }
            return .whisper(modelPath: modelPath)
        case .parakeet:
            guard modelDownloadManager.isParakeetDownloaded else { return nil }
            return .parakeet
        }
    }

    private func transcribe(_ samples: [Float], using route: TranscriptionRoute) async throws -> String {
        switch route {
        case .whisper(let modelPath):
            return try await transcriber.transcribe(samples: samples, modelPath: modelPath)
        case .parakeet:
            return try await parakeetTranscriber.transcribe(samples: samples)
        }
    }

    private func finishRecordingAndTranscribe() {
        let samples = audioCaptureManager.stopRecording()
        guard samples.count >= Self.minimumSampleCount else {
            logger.info("Skipping transcription — only \(samples.count, privacy: .public) samples (accidental tap?)")
            return
        }

        guard let route = currentTranscriptionRoute() else {
            logger.error("No transcription model selected")
            transcriptionError = "No transcription model selected. Pick one in Settings."
            return
        }

        isTranscribing = true
        transcriptionError = nil

        logger.info("Transcribing \(samples.count, privacy: .public) samples with \(route.logDescription, privacy: .public)")

        let cleanupRepoID = cleanupModelManager.selectedHubRepoID
        // Snapshotted here rather than read inside the task: the pipeline
        // runs off the main actor, and an edit made mid-dictation
        // shouldn't change the rules halfway through.
        let vocabulary = vocabularyStore.termStrings
        // Stamped now, not when the model finishes: transcription time
        // varies with utterance length, so two dictations in quick
        // succession can complete out of order. This is the timestamp the
        // history is sorted by.
        let recordedAt = Date()

        Task { [weak self, transcriber, parakeetTranscriber, cleanupEngine, logger] in
            do {
                // Hops to the transcriber actor's executor — the blocking
                // inference call runs there, not on the main actor.
                let rawText: String
                switch route {
                case .whisper(let modelPath):
                    rawText = try await transcriber.transcribe(samples: samples, modelPath: modelPath)
                case .parakeet:
                    rawText = try await parakeetTranscriber.transcribe(samples: samples)
                }
                logger.info("Transcription finished — \(rawText.count, privacy: .public) chars")

                // Fix custom spellings before cleanup, so the LLM reads
                // the proper nouns as the user spells them rather than
                // "correcting" a mangled version into something else.
                var finalText = VocabularyCorrector.apply(rawText, terms: vocabulary)
                if !finalText.isEmpty, let cleanupRepoID {
                    do {
                        let cleaned = try await cleanupEngine.cleanup(finalText, hubRepoID: cleanupRepoID)
                        // Applied again on the way out: the cleanup model
                        // is free to rewrite anything, including a term it
                        // has never seen.
                        finalText = VocabularyCorrector.apply(cleaned, terms: vocabulary)
                        logger.info("Cleanup finished — \(finalText.count, privacy: .public) chars")
                    } catch {
                        // Cleanup is best-effort: fall back to the raw
                        // transcript rather than dropping the dictation.
                        logger.error("Cleanup failed, using raw transcript: \(error.localizedDescription, privacy: .public)")
                    }
                }

                guard let self else { return }
                self.isTranscribing = false
                guard !finalText.isEmpty else { return }

                self.record(TranscriptEntry(date: recordedAt, text: finalText, rawText: rawText))
                self.textInjector.inject(finalText)
            } catch {
                guard let self else { return }
                self.isTranscribing = false
                self.transcriptionError = error.localizedDescription
                logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Files a finished dictation into the history at the position its
    /// recording time earns it — not simply at the top. Transcription
    /// tasks can finish out of order, so inserting at index 0 unconditionally
    /// is what used to leave the list showing an older transcript above a
    /// newer one.
    private func record(_ entry: TranscriptEntry) {
        let index = transcriptHistory.firstIndex { $0.date <= entry.date } ?? transcriptHistory.count
        transcriptHistory.insert(entry, at: index)
        if transcriptHistory.count > TranscriptStore.maxEntries {
            transcriptHistory.removeLast(transcriptHistory.count - TranscriptStore.maxEntries)
        }
        lastTranscript = transcriptHistory.first?.text ?? entry.text
        transcriptStore.save(transcriptHistory)
    }

    func clearTranscriptHistory() {
        transcriptHistory.removeAll()
        lastTranscript = ""
        transcriptStore.save(transcriptHistory)
    }

    /// Runs cleanup on arbitrary text with the currently selected (or
    /// default recommended) cleanup model. Used by the debug cleanup lab.
    func runCleanup(_ text: String) async throws -> String {
        try await cleanupEngine.cleanup(text, hubRepoID: cleanupModelManager.effectiveHubRepoID)
    }

    /// Command-line hook for verifying cleanup behavior without clicking
    /// through the Cleanup Lab UI: launch with
    /// `DAEMONFLOW_SELFTEST_CLEANUP=1` and watch the "selftest" log
    /// category. Runs every DebugCleanupView.TestCase against the
    /// recommended cleanup model (bypassing selection state entirely, so
    /// it works even before onboarding is complete) and logs raw/cleaned
    /// pairs. No-ops in normal launches.
    private func runCleanupSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["DAEMONFLOW_SELFTEST_CLEANUP"] == "1" else { return }

        let selftestLogger = Logger(subsystem: daemonFlowLogSubsystem, category: "selftest")
        let repoID = CleanupModelCatalog.recommendedModel.hubRepoID

        Task { [cleanupEngine] in
            selftestLogger.info("Cleanup self-test starting — model: \(repoID, privacy: .public)")
            for testCase in DebugCleanupView.testCases {
                do {
                    let cleaned = try await cleanupEngine.cleanup(testCase.input, hubRepoID: repoID)
                    selftestLogger.info("[\(testCase.name, privacy: .public)] RAW: \(testCase.input, privacy: .public)")
                    selftestLogger.info("[\(testCase.name, privacy: .public)] CLEANED: \(cleaned, privacy: .public)")
                } catch {
                    selftestLogger.error("[\(testCase.name, privacy: .public)] FAILED: \(error.localizedDescription, privacy: .public)")
                }
            }
            selftestLogger.info("Cleanup self-test finished")
        }
    }

    private static func computeOnboardingComplete(
        _ transcription: ModelDownloadManager,
        _ cleanup: CleanupModelManager
    ) -> Bool {
        transcription.hasUsableTranscriptionModel && cleanup.selectedHubRepoID != nil
    }

    private static func computePermissionsGranted(
        _ hotkey: HotkeyManager,
        _ audio: AudioCaptureManager
    ) -> Bool {
        !hotkey.needsAccessibilityPermission
            && !hotkey.needsInputMonitoringPermission
            && audio.micPermissionGranted
    }
}
