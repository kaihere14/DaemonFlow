//
//  CleanupModelCatalog.swift
//  DaemonFlow
//

import Foundation

struct CleanupModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let tagline: String
    let hubRepoID: String
    let sizeDescription: String
    let speedDescription: String
    let qualityDescription: String
    let recommended: Bool
}

enum CleanupModelCatalog {
    static let all: [CleanupModel] = [
        CleanupModel(
            id: "llama-3.2-1b",
            displayName: "Llama 3.2 1B",
            tagline: "Fastest option, best for low-end Macs.",
            hubRepoID: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            sizeDescription: "700 MB",
            speedDescription: "Fastest",
            qualityDescription: "Basic corrections",
            recommended: false
        ),
        CleanupModel(
            id: "llama-3.2-3b",
            displayName: "Llama 3.2 3B",
            tagline: "The best balance of speed and quality.",
            hubRepoID: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            sizeDescription: "1.8 GB",
            speedDescription: "Fast",
            qualityDescription: "Very good",
            recommended: true
        ),
        CleanupModel(
            id: "qwen-2.5-3b",
            displayName: "Qwen 2.5 3B",
            tagline: "Solid alternative with strong multilingual support.",
            hubRepoID: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            sizeDescription: "1.8 GB",
            speedDescription: "Fast",
            qualityDescription: "Very good, multilingual",
            recommended: false
        ),
        CleanupModel(
            id: "phi-3.5-mini",
            displayName: "Phi 3.5 Mini",
            tagline: "Stronger instruction-following, moderate speed.",
            hubRepoID: "mlx-community/Phi-3.5-mini-instruct-4bit",
            sizeDescription: "2.2 GB",
            speedDescription: "Moderate",
            qualityDescription: "Strong",
            recommended: false
        ),
        CleanupModel(
            id: "llama-3.1-8b",
            displayName: "Llama 3.1 8B",
            tagline: "Best quality, slower — recommend 16GB+ RAM.",
            hubRepoID: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            sizeDescription: "4.5 GB",
            speedDescription: "Slower",
            qualityDescription: "Best",
            recommended: false
        ),
    ]

    static var recommendedModel: CleanupModel {
        all.first(where: \.recommended) ?? all[0]
    }

    static func model(forHubRepoID hubRepoID: String) -> CleanupModel? {
        all.first { $0.hubRepoID == hubRepoID }
    }
}
