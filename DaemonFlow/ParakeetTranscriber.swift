//
//  ParakeetTranscriber.swift
//  DaemonFlow
//

import FluidAudio
import Foundation
import os

enum ParakeetTranscriberError: Error, LocalizedError {
    case modelNotDownloaded

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "The Parakeet model isn't downloaded yet. Select it again in Settings to download it."
        }
    }
}

/// Download location and state for the Parakeet CoreML bundle, mirroring
/// CleanupModelStorage's role for MLX models. FluidAudio owns the on-disk
/// layout (a `.mlmodelc` bundle per stage plus a vocabulary JSON under
/// Application Support/FluidAudio/Models), and its download/load/exists
/// calls only agree with each other on that default path — so we use it
/// rather than nesting the bundle under DaemonFlow's own model folders.
nonisolated enum ParakeetModelStorage {
    /// v3 is the multilingual TDT variant (25 European languages).
    static let version: AsrModelVersion = .v3

    static var cacheDirectory: URL {
        AsrModels.defaultCacheDirectory(for: version)
    }

    static var isDownloaded: Bool {
        AsrModels.modelsExist(at: cacheDirectory, version: version)
    }

    /// Fetches the CoreML bundle without loading it into memory — the
    /// counterpart to LLMCleanupEngine.downloadModelFiles, so the picker
    /// card can show progress and the actual load stays lazy.
    static func download(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await AsrModels.download(version: version) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }
}

/// Serializes all FluidAudio access on this actor's executor, keeping
/// CoreML model loading and inference off the main actor. Mirrors
/// WhisperTranscriber: the loaded models stay resident between utterances
/// and are only built once.
actor ParakeetTranscriber {
    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "parakeet")

    private var manager: AsrManager?
    private var decoderLayerCount = 2

    /// Transcribes 16kHz mono Float32 PCM samples — the same buffer shape
    /// WhisperTranscriber takes, so the two engines are interchangeable
    /// from the pipeline's point of view.
    func transcribe(samples: [Float]) async throws -> String {
        let manager = try await loadedManager()
        // The TDT decoder state is per-utterance: each dictation is an
        // independent transcription, so carrying state across them would
        // leak the previous utterance's tokens into this one.
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadedManager() async throws -> AsrManager {
        if let manager { return manager }

        guard ParakeetModelStorage.isDownloaded else {
            throw ParakeetTranscriberError.modelNotDownloaded
        }

        logger.info("Loading Parakeet models from \(ParakeetModelStorage.cacheDirectory.path, privacy: .public)")
        let models = try await AsrModels.load(
            from: ParakeetModelStorage.cacheDirectory,
            version: ParakeetModelStorage.version
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        decoderLayerCount = await manager.decoderLayerCount
        self.manager = manager
        logger.info("Parakeet models loaded")
        return manager
    }
}
