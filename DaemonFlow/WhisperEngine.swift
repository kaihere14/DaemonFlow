//
//  WhisperEngine.swift
//  DaemonFlow
//

import Foundation

enum WhisperEngineError: Error, LocalizedError {
    case modelLoadFailed(path: String)
    case noModelLoaded
    case transcriptionFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path):
            return "Couldn't load Whisper model at \(path). The file may be missing or corrupt."
        case .noModelLoaded:
            return "No Whisper model is loaded."
        case .transcriptionFailed(let code):
            return "Transcription failed (whisper_full returned \(code))."
        }
    }
}

/// Thin Swift wrapper around whisper.cpp's C API. Nonisolated so a later
/// audio pipeline can run transcription off the main thread — whisper_full
/// blocks for the duration of inference.
nonisolated final class WhisperEngine {
    private var context: OpaquePointer?

    /// whisper_full_params.language keeps a borrowed C-string pointer for
    /// the duration of the call; a leaked strdup is immortal and therefore
    /// always valid.
    private static let englishLanguage: UnsafePointer<CChar> = UnsafePointer(strdup("en")!)

    deinit {
        if let context {
            whisper_free(context)
        }
    }

    var isModelLoaded: Bool { context != nil }

    func loadModel(at path: URL) throws {
        unloadModel()

        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = true

        guard let newContext = whisper_init_from_file_with_params(path.path, contextParams) else {
            throw WhisperEngineError.modelLoadFailed(path: path.path)
        }
        context = newContext
    }

    func unloadModel() {
        if let context {
            whisper_free(context)
        }
        context = nil
    }

    /// Transcribes 16kHz mono Float32 PCM samples and returns the full text.
    ///
    /// `prompt` is fed to the decoder as if it were preceding speech, which
    /// biases it toward the spellings it contains — the documented way to
    /// teach Whisper names and jargon it would otherwise mishear.
    func transcribe(samples: [Float], prompt: String? = nil) throws -> String {
        guard let context else {
            throw WhisperEngineError.noModelLoaded
        }
        guard !samples.isEmpty else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.no_context = true
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.language = Self.englishLanguage
        params.n_threads = Int32(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))

        let result: Int32
        if let prompt, !prompt.isEmpty {
            // Only borrowed for the duration of whisper_full.
            result = prompt.withCString { promptPointer in
                var promptedParams = params
                promptedParams.initial_prompt = promptPointer
                return Self.run(context, promptedParams, samples)
            }
        } else {
            result = Self.run(context, params, samples)
        }
        guard result == 0 else {
            throw WhisperEngineError.transcriptionFailed(code: result)
        }

        var transcript = ""
        let segmentCount = whisper_full_n_segments(context)
        for index in 0..<segmentCount {
            if let segmentText = whisper_full_get_segment_text(context, index) {
                transcript += String(cString: segmentText)
            }
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(_ context: OpaquePointer, _ params: whisper_full_params, _ samples: [Float]) -> Int32 {
        samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
    }
}
