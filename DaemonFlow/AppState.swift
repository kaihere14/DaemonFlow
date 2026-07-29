//
//  AppState.swift
//  DaemonFlow
//

import Combine
import Foundation
import os

struct TranscriptEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let text: String
}

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
    private var hudController: RecordingHUDController?

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

    /// ⌥1 refine lifecycle: drives the HUD's shimmering "Refining" label
    /// while in flight and the brief "Done" confirmation after the paste.
    enum RefinePhase: Equatable {
        case idle
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

        Publishers.CombineLatest3(hotkeyManager.$isRecording, $isTranscribing, $refinePhase)
            .map { isRecording, isTranscribing, refinePhase -> HUDState in
                if isRecording { return .recording }
                if isTranscribing { return .processing }
                switch refinePhase {
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

    /// ⌥1 pressed: capture the selection in the frontmost app, refine it
    /// with the cleanup model, and paste the result back over the
    /// selection. Best-effort — no selection or a model error just logs
    /// and leaves the user's text untouched.
    private func refineSelection() {
        guard refinePhase == .idle else { return }
        refinePhase = .refining

        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let selected = await self.selectionRefiner.captureSelectedText() else {
                self.refinePhase = .idle
                return
            }

            let repoID = self.cleanupModelManager.effectiveHubRepoID
            do {
                let refined = try await self.cleanupEngine.refine(selected, hubRepoID: repoID)
                guard !refined.isEmpty else {
                    self.refinePhase = .idle
                    return
                }
                self.textInjector.inject(refined)

                // Brief "Done" confirmation in the HUD, then hide.
                self.refinePhase = .done
                try? await Task.sleep(for: .seconds(2))
                if self.refinePhase == .done {
                    self.refinePhase = .idle
                }
            } catch {
                self.logger.error("Refine failed: \(error.localizedDescription, privacy: .public)")
                self.refinePhase = .idle
            }
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

                self.lastTranscript = finalText
                self.transcriptHistory.insert(TranscriptEntry(date: Date(), text: finalText), at: 0)
                self.textInjector.inject(finalText)
            } catch {
                guard let self else { return }
                self.isTranscribing = false
                self.transcriptionError = error.localizedDescription
                logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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
