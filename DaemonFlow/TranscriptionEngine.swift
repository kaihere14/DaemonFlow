//
//  TranscriptionEngine.swift
//  DaemonFlow
//

import Foundation

/// Which speech-to-text backend turns recorded audio into text. Both
/// engines run fully locally; they differ in model format and runtime —
/// Whisper is whisper.cpp/GGML on the GPU, Parakeet is CoreML on the
/// Apple Neural Engine.
enum TranscriptionEngine: String, CaseIterable, Sendable {
    case whisper
    case parakeet
}

/// A resolved transcription target: the engine plus whatever that engine
/// needs to run. Resolved on the main actor before recording is handed
/// off, so the background transcription task never has to hop back to
/// read selection state mid-flight.
enum TranscriptionRoute: Sendable {
    case whisper(modelPath: URL)
    case parakeet

    var logDescription: String {
        switch self {
        case .whisper(let modelPath): return modelPath.lastPathComponent
        case .parakeet: return ParakeetModelCatalog.defaultModel.displayName
        }
    }
}
