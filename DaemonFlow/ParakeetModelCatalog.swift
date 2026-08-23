//
//  ParakeetModelCatalog.swift
//  DaemonFlow
//

import Foundation

/// A Parakeet variant offered in the model picker. Parallels WhisperModel,
/// minus the download URL and file name: FluidAudio owns the Parakeet
/// download (a multi-file CoreML bundle) and its own on-disk layout, so
/// there is no single file for us to point at.
struct ParakeetModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let tagline: String
    let sizeDescription: String
    let speedDescription: String
    let accuracyDescription: String
    let recommended: Bool
}

enum ParakeetModelCatalog {
    static let all: [ParakeetModel] = [
        ParakeetModel(
            id: "parakeet-tdt-0.6b-v3",
            displayName: "Parakeet TDT 0.6B",
            tagline: "NVIDIA ASR on the Neural Engine — very fast, low power.",
            sizeDescription: "490 MB",
            speedDescription: "Fastest",
            accuracyDescription: "Strong, multilingual",
            recommended: false
        )
    ]

    /// The variant selected when the user picks the Parakeet engine.
    /// Single-entry today; kept as a lookup so adding a second variant
    /// doesn't change call sites.
    static var defaultModel: ParakeetModel { all[0] }
}
