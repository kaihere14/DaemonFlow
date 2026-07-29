//
//  ModelCatalog.swift
//  DaemonFlow
//

import Foundation

struct WhisperModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let tagline: String
    let fileName: String
    let downloadURL: URL
    let sizeDescription: String
    let speedDescription: String
    let accuracyDescription: String
    let recommended: Bool
}

enum WhisperModelCatalog {
    private static let baseURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/")!

    static let all: [WhisperModel] = [
        WhisperModel(
            id: "tiny.en",
            displayName: "Tiny (English)",
            tagline: "Fastest option, good for low-end Macs.",
            fileName: "ggml-tiny.en.bin",
            downloadURL: baseURL.appendingPathComponent("ggml-tiny.en.bin"),
            sizeDescription: "75 MB",
            speedDescription: "Fastest",
            accuracyDescription: "Basic",
            recommended: false
        ),
        WhisperModel(
            id: "base.en",
            displayName: "Base (English)",
            tagline: "Very fast with decent accuracy.",
            fileName: "ggml-base.en.bin",
            downloadURL: baseURL.appendingPathComponent("ggml-base.en.bin"),
            sizeDescription: "142 MB",
            speedDescription: "Very fast",
            accuracyDescription: "Decent",
            recommended: false
        ),
        WhisperModel(
            id: "small.en",
            displayName: "Small (English)",
            tagline: "The best balance of speed and accuracy.",
            fileName: "ggml-small.en.bin",
            downloadURL: baseURL.appendingPathComponent("ggml-small.en.bin"),
            sizeDescription: "466 MB",
            speedDescription: "Balanced",
            accuracyDescription: "Very good",
            recommended: true
        ),
        WhisperModel(
            id: "medium.en",
            displayName: "Medium (English)",
            tagline: "Strong accuracy, noticeably slower.",
            fileName: "ggml-medium.en.bin",
            downloadURL: baseURL.appendingPathComponent("ggml-medium.en.bin"),
            sizeDescription: "1.5 GB",
            speedDescription: "Slower",
            accuracyDescription: "Strong",
            recommended: false
        ),
        WhisperModel(
            id: "large-v3-turbo",
            displayName: "Large v3 Turbo",
            tagline: "Best accuracy, multilingual, optimized for speed.",
            fileName: "ggml-large-v3-turbo.bin",
            downloadURL: baseURL.appendingPathComponent("ggml-large-v3-turbo.bin"),
            sizeDescription: "1.5 GB",
            speedDescription: "Optimized",
            accuracyDescription: "Best, multilingual",
            recommended: false
        ),
    ]
}
