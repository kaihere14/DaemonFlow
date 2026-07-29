//
//  ModelDownloadManager.swift
//  DaemonFlow
//

import Foundation
import Combine

@MainActor
final class ModelDownloadManager: ObservableObject {
    private static let selectedModelDefaultsKey = "selectedWhisperModel"

    /// Source of truth for the current selection. @Published so any view
    /// reading `isSelected(_:)` re-renders when the selection changes,
    /// whether from a fresh download or from picking an already-downloaded model.
    @Published private(set) var selectedFileName: String?

    @Published private(set) var progressByModelID: [String: Double] = [:]
    @Published private(set) var downloadingModelIDs: Set<String> = []
    @Published private(set) var errorByModelID: [String: String] = [:]

    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private var progressObservations: [String: NSKeyValueObservation] = [:]
    private let session = URLSession(configuration: .default)

    private var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("DaemonFlow/Models", isDirectory: true)
    }

    init() {
        selectedFileName = UserDefaults.standard.string(forKey: Self.selectedModelDefaultsKey)
    }

    // MARK: - Paths & selection state

    func localFileURL(for model: WhisperModel) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName)
    }

    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: localFileURL(for: model).path)
    }

    func hasAnyDownloadedModel() -> Bool {
        WhisperModelCatalog.all.contains { isModelDownloaded($0) }
    }

    /// Full path to the currently selected model's file, per UserDefaults.
    func selectedModelPath() -> URL? {
        guard let selectedFileName else { return nil }
        return modelsDirectory.appendingPathComponent(selectedFileName)
    }

    func isSelected(_ model: WhisperModel) -> Bool {
        selectedFileName == model.fileName
    }

    /// Update the persisted selection without downloading anything.
    func selectModel(_ model: WhisperModel) {
        UserDefaults.standard.set(model.fileName, forKey: Self.selectedModelDefaultsKey)
        selectedFileName = model.fileName
    }

    // MARK: - Downloading

    func downloadModel(_ model: WhisperModel) {
        guard !downloadingModelIDs.contains(model.id) else { return }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
            errorByModelID[model.id] = "Couldn't create models folder: \(error.localizedDescription)"
            return
        }

        errorByModelID[model.id] = nil
        progressByModelID[model.id] = 0
        downloadingModelIDs.insert(model.id)

        let destination = localFileURL(for: model)

        let task = session.downloadTask(with: model.downloadURL) { [weak self] tempURL, _, error in
            guard let self else { return }
            Task { @MainActor in
                self.finishDownload(model: model, tempURL: tempURL, error: error, destination: destination)
            }
        }

        progressObservations[model.id] = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            guard let self else { return }
            Task { @MainActor in
                self.progressByModelID[model.id] = progress.fractionCompleted
            }
        }

        activeTasks[model.id] = task
        task.resume()
    }

    func cancelDownload(_ model: WhisperModel) {
        activeTasks[model.id]?.cancel()
        cleanUp(modelID: model.id)
    }

    private func finishDownload(model: WhisperModel, tempURL: URL?, error: Error?, destination: URL) {
        defer { cleanUp(modelID: model.id) }

        if let error {
            let nsError = error as NSError
            let wasCancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
            if !wasCancelled {
                errorByModelID[model.id] = error.localizedDescription
            }
            return
        }

        guard let tempURL else {
            errorByModelID[model.id] = "Download failed: no file was received."
            return
        }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: tempURL, to: destination)
            selectModel(model)
        } catch {
            errorByModelID[model.id] = "Couldn't save model: \(error.localizedDescription)"
        }
    }

    private func cleanUp(modelID: String) {
        downloadingModelIDs.remove(modelID)
        activeTasks[modelID] = nil
        progressObservations[modelID]?.invalidate()
        progressObservations[modelID] = nil
    }
}
