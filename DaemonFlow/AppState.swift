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
    let hudModel = HUDModel()

    private let transcriber = WhisperTranscriber()
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

    /// Drives root view routing: true once both a Whisper model and a
    /// cleanup model have been selected (two-step onboarding complete).
    @Published private(set) var hasCompletedOnboarding: Bool

    /// Sheet triggers for the standalone model pickers and cleanup lab.
    @Published var isPresentingModelPicker = false
    @Published var isPresentingCleanupPicker = false
    @Published var isPresentingCleanupLab = false

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

        Publishers.CombineLatest(modelDownloadManager.$selectedFileName, cleanupModelManager.$selectedHubRepoID)
            .sink { [weak self] _, _ in
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
                } else {
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

        Publishers.CombineLatest3(hotkeyManager.$isRecording, $isTranscribing, $refinePhase)
            .map { isRecording, isTranscribing, refinePhase -> HUDState in
                if isRecording { return .recording }
                if isTranscribing { return .processing }
                switch refinePhase {
                case .listening: return .instructing
                case .refining: return .refining
                case .done: return .done
                case .idle: return .hidden
                }
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [hudModel] state in
                hudModel.state = state
            }
            .store(in: &cancellables)
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
        guard let modelPath = modelDownloadManager.selectedModelPath() else {
            logger.error("Instructed refine: no Whisper model selected — falling back to plain refine")
            return nil
        }

        do {
            let instruction = try await transcriber.transcribe(samples: samples, modelPath: modelPath)
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

    private func finishRecordingAndTranscribe() {
        let samples = audioCaptureManager.stopRecording()
        guard samples.count >= Self.minimumSampleCount else {
            logger.info("Skipping transcription — only \(samples.count, privacy: .public) samples (accidental tap?)")
            return
        }

        guard let modelPath = modelDownloadManager.selectedModelPath() else {
            logger.error("No Whisper model selected")
            transcriptionError = "No Whisper model selected. Pick one in Settings."
            return
        }

        isTranscribing = true
        transcriptionError = nil

        logger.info("Transcribing \(samples.count, privacy: .public) samples with \(modelPath.lastPathComponent, privacy: .public)")

        let cleanupRepoID = cleanupModelManager.selectedHubRepoID
        // Stamped now, not when the model finishes: transcription time
        // varies with utterance length, so two dictations in quick
        // succession can complete out of order. This is the timestamp the
        // history is sorted by.
        let recordedAt = Date()

        Task { [weak self, transcriber, cleanupEngine, logger] in
            do {
                // Hops to the transcriber actor's executor — the blocking
                // whisper_full call runs there, not on the main actor.
                let rawText = try await transcriber.transcribe(samples: samples, modelPath: modelPath)
                logger.info("Transcription finished — \(rawText.count, privacy: .public) chars")

                var finalText = rawText
                if !rawText.isEmpty, let cleanupRepoID {
                    do {
                        finalText = try await cleanupEngine.cleanup(rawText, hubRepoID: cleanupRepoID)
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
        _ whisper: ModelDownloadManager,
        _ cleanup: CleanupModelManager
    ) -> Bool {
        let whisperReady = whisper.selectedModelPath() != nil || whisper.hasAnyDownloadedModel()
        return whisperReady && cleanup.selectedHubRepoID != nil
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
