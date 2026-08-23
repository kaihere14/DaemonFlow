//
//  ModelDownloadManager.swift
//  DaemonFlow
//

import Foundation
import Combine

@MainActor
final class ModelDownloadManager: ObservableObject {
    private static let selectedModelDefaultsKey = "selectedWhisperModel"
    private static let selectedEngineDefaultsKey = "selectedTranscriptionEngine"

    /// Which backend transcribes dictation. Persisted separately from the
    /// Whisper file name so switching to Parakeet and back doesn't lose
    /// which Whisper model was picked. Defaults to Whisper, which is what
    /// every install before Parakeet existed was already using.
    @Published private(set) var selectedEngine: TranscriptionEngine

    /// Source of truth for the current Whisper selection. @Published so any view
    /// reading `isSelected(_:)` re-renders when the selection changes,
    /// whether from a fresh download or from picking an already-downloaded model.
    @Published private(set) var selectedFileName: String?

    /// Cached disk check for the Parakeet bundle. Published because
    /// `AsrModels.modelsExist` walks the file system — views ask for it on
    /// every render, and it has to invalidate when a download finishes.
    @Published private(set) var isParakeetDownloaded: Bool

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
        selectedEngine = UserDefaults.standard.string(forKey: Self.selectedEngineDefaultsKey)
            .flatMap(TranscriptionEngine.init(rawValue:)) ?? .whisper
        isParakeetDownloaded = ParakeetModelStorage.isDownloaded
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
        selectedEngine == .whisper && selectedFileName == model.fileName
    }

    /// Update the persisted selection without downloading anything.
    func selectModel(_ model: WhisperModel) {
        UserDefaults.standard.set(model.fileName, forKey: Self.selectedModelDefaultsKey)
        selectedFileName = model.fileName
        selectEngine(.whisper)
    }

    /// True once the current engine has a model the pipeline can actually
    /// run with — the gate onboarding completion is measured against.
    var hasUsableTranscriptionModel: Bool {
        switch selectedEngine {
        case .whisper:
            return selectedModelPath() != nil || hasAnyDownloadedModel()
        case .parakeet:
            return isParakeetDownloaded
        }
    }

    /// Label for the selected transcription model, as shown in Settings.
    var selectedModelDisplayName: String? {
        switch selectedEngine {
        case .whisper:
            return selectedFileName
        case .parakeet:
            return ParakeetModelCatalog.defaultModel.displayName
        }
    }

    // MARK: - Parakeet

    func isModelDownloaded(_ model: ParakeetModel) -> Bool {
        isParakeetDownloaded
    }

    func isSelected(_ model: ParakeetModel) -> Bool {
        selectedEngine == .parakeet
    }

    func selectModel(_ model: ParakeetModel) {
        selectEngine(.parakeet)
    }

    /// Downloads the Parakeet CoreML bundle, then selects it — the same
    /// download-and-select contract the Whisper cards have. Loading into
    /// memory stays lazy until the first dictation.
    func downloadModel(_ model: ParakeetModel) {
        guard !downloadingModelIDs.contains(model.id) else { return }

        errorByModelID[model.id] = nil
        progressByModelID[model.id] = 0
        downloadingModelIDs.insert(model.id)

        Task { [weak self] in
            do {
                try await ParakeetModelStorage.download { fraction in
                    Task { @MainActor [weak self] in
                        self?.progressByModelID[model.id] = fraction
                    }
                }
                guard let self else { return }
                self.downloadingModelIDs.remove(model.id)
                self.isParakeetDownloaded = ParakeetModelStorage.isDownloaded
                self.selectModel(model)
            } catch {
                guard let self else { return }
                self.downloadingModelIDs.remove(model.id)
                self.errorByModelID[model.id] = error.localizedDescription
            }
        }
    }

    private func selectEngine(_ engine: TranscriptionEngine) {
        UserDefaults.standard.set(engine.rawValue, forKey: Self.selectedEngineDefaultsKey)
        selectedEngine = engine
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
