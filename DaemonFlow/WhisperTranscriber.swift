//
//  WhisperTranscriber.swift
//  DaemonFlow
//

import Foundation

/// Serializes all WhisperEngine access on this actor's executor, keeping
/// model loading and the blocking whisper_full call off the main actor.
/// The loaded model is kept resident between utterances and only reloaded
/// when the selected model path changes.
actor WhisperTranscriber {
    private let engine = WhisperEngine()
    private var loadedModelPath: URL?

    func transcribe(samples: [Float], modelPath: URL) throws -> String {
        if loadedModelPath != modelPath || !engine.isModelLoaded {
            try engine.loadModel(at: modelPath)
            loadedModelPath = modelPath
        }
        return try engine.transcribe(samples: samples)
    }
}
