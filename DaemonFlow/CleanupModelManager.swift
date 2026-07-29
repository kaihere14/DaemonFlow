//
//  CleanupModelManager.swift
//  DaemonFlow
//

import Combine
import Foundation

/// Selection persistence and download state for cleanup LLM models.
/// Downloads are performed by LLMCleanupEngine (via Hugging Face Hub);
/// this manager drives them and republishes progress for the cards UI.
@MainActor
final class CleanupModelManager: ObservableObject {
    private static let selectedModelDefaultsKey = "selectedCleanupModel"

    /// Explicit user selection (hubRepoID); nil until onboarding step 2
    /// has been completed.
    @Published private(set) var selectedHubRepoID: String?

    @Published private(set) var progressByModelID: [String: Double] = [:]
    @Published private(set) var downloadingModelIDs: Set<String> = []
    @Published private(set) var errorByModelID: [String: String] = [:]

    private let engine: LLMCleanupEngine

    init(engine: LLMCleanupEngine) {
        self.engine = engine
        selectedHubRepoID = UserDefaults.standard.string(forKey: Self.selectedModelDefaultsKey)
    }

    /// The repo to use for cleanup: explicit selection, else the
    /// recommended default.
    var effectiveHubRepoID: String {
        selectedHubRepoID ?? CleanupModelCatalog.recommendedModel.hubRepoID
    }

    func isModelDownloaded(_ model: CleanupModel) -> Bool {
        CleanupModelStorage.isDownloaded(hubRepoID: model.hubRepoID)
    }

    func isSelected(_ model: CleanupModel) -> Bool {
        selectedHubRepoID == model.hubRepoID
    }

    /// Select an already-downloaded model — persists the choice only; the
    /// engine reloads lazily on the next cleanup() call.
    func selectModel(_ model: CleanupModel) {
        UserDefaults.standard.set(model.hubRepoID, forKey: Self.selectedModelDefaultsKey)
        selectedHubRepoID = model.hubRepoID
    }

    /// Downloads model files (not a full memory load — see
    /// LLMCleanupEngine.downloadModelFiles), then selects. Multiple cards
    /// can be downloading at once: downloadModelFiles is nonisolated and
    /// doesn't serialize behind the engine actor, so each model's Task
    /// here proceeds independently with its own progress.
    func downloadAndSelect(_ model: CleanupModel) {
        guard !downloadingModelIDs.contains(model.id) else { return }

        errorByModelID[model.id] = nil
        progressByModelID[model.id] = 0
        downloadingModelIDs.insert(model.id)

        Task { [weak self, engine] in
            do {
                try await engine.downloadModelFiles(hubRepoID: model.hubRepoID) { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.progressByModelID[model.id] = fraction
                    }
                }
                guard let self else { return }
                self.downloadingModelIDs.remove(model.id)
                self.selectModel(model)
            } catch {
                guard let self else { return }
                self.downloadingModelIDs.remove(model.id)
                self.errorByModelID[model.id] = error.localizedDescription
            }
        }
    }
}
