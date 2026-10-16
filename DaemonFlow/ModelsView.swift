//
//  ModelsView.swift
//  DaemonFlow
//
//  Model lists, shared by the Models pane and the onboarding steps. Each
//  model is one row: name and trade-offs on the left, and on the right the
//  single action that makes sense for it right now.
//

import SwiftUI

struct ModelsView: View {
    var body: some View {
        Form {
            Section {
                TranscriptionModelList()
            } header: {
                Text("Transcription")
            } footer: {
                Text("Turns your speech into text, entirely on this Mac. Larger models are more accurate and a little slower.")
            }

            Section {
                CleanupModelList()
            } header: {
                Text("Cleanup")
            } footer: {
                Text("A small local language model removes filler words, applies self-corrections and fixes punctuation before anything is pasted.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lists

struct TranscriptionModelList: View {
    @EnvironmentObject private var downloadManager: ModelDownloadManager

    var body: some View {
        ForEach(WhisperModelCatalog.all) { model in
            ModelRow(
                title: model.displayName,
                tagline: model.tagline,
                specs: [model.sizeDescription, model.speedDescription, model.accuracyDescription],
                recommended: model.recommended,
                status: status(of: model),
                error: downloadManager.errorByModelID[model.id],
                onDownload: { downloadManager.downloadModel(model) },
                onSelect: { downloadManager.selectModel(model) }
            )
        }
        ForEach(ParakeetModelCatalog.all) { model in
            ModelRow(
                title: model.displayName,
                tagline: model.tagline,
                specs: [model.sizeDescription, model.speedDescription, model.accuracyDescription],
                recommended: model.recommended,
                status: status(of: model),
                error: downloadManager.errorByModelID[model.id],
                onDownload: { downloadManager.downloadModel(model) },
                onSelect: { downloadManager.selectModel(model) }
            )
        }
    }

    private func status(of model: WhisperModel) -> ModelStatus {
        if downloadManager.isSelected(model) { return .selected }
        if downloadManager.downloadingModelIDs.contains(model.id) {
            return .downloading(downloadManager.progressByModelID[model.id] ?? 0)
        }
        return downloadManager.isModelDownloaded(model) ? .downloaded : .notDownloaded
    }

    private func status(of model: ParakeetModel) -> ModelStatus {
        if downloadManager.isSelected(model) { return .selected }
        if downloadManager.downloadingModelIDs.contains(model.id) {
            return .downloading(downloadManager.progressByModelID[model.id] ?? 0)
        }
        return downloadManager.isModelDownloaded(model) ? .downloaded : .notDownloaded
    }
}

struct CleanupModelList: View {
    @EnvironmentObject private var cleanupManager: CleanupModelManager

    var body: some View {
        ForEach(CleanupModelCatalog.all) { model in
            ModelRow(
                title: model.displayName,
                tagline: model.tagline,
                specs: [model.sizeDescription, model.speedDescription, model.qualityDescription],
                recommended: model.recommended,
                status: status(of: model),
                error: cleanupManager.errorByModelID[model.id],
                onDownload: { cleanupManager.downloadAndSelect(model) },
                onSelect: { cleanupManager.selectModel(model) }
            )
        }
    }

    private func status(of model: CleanupModel) -> ModelStatus {
        if cleanupManager.isSelected(model) { return .selected }
        if cleanupManager.downloadingModelIDs.contains(model.id) {
            return .downloading(cleanupManager.progressByModelID[model.id] ?? 0)
        }
        return cleanupManager.isModelDownloaded(model) ? .downloaded : .notDownloaded
    }
}

// MARK: - Row

enum ModelStatus: Equatable {
    case notDownloaded
    case downloading(Double)
    case downloaded
    case selected

    /// Identity for the trailing control. Progress is deliberately left
    /// out, so a download ticking forward doesn't re-run the swap.
    var phase: Int {
        switch self {
        case .notDownloaded: 0
        case .downloading: 1
        case .downloaded: 2
        case .selected: 3
        }
    }
}

struct ModelRow: View {
    let title: String
    let tagline: String
    let specs: [String]
    let recommended: Bool
    let status: ModelStatus
    let error: String?
    let onDownload: () -> Void
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .fontWeight(.medium)
                    if recommended {
                        RecommendedTag()
                    }
                }

                Text(tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(specs.joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            ZStack(alignment: .trailing) {
                trailing
                    .id(status.phase)
                    .transition(trailingTransition)
            }
            .frame(minWidth: 96, alignment: .trailing)
            .animation(Motion.iconSwap, value: status.phase)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // A downloaded model can be picked by clicking anywhere on its
        // row, the way a list of radio choices works.
        .onTapGesture {
            if status == .downloaded { onSelect() }
        }
        .accessibilityElement(children: .contain)
    }

    private var trailingTransition: AnyTransition {
        status == .selected
            ? AnyTransition(IconSwapTransition(reduceMotion: reduceMotion))
            : AnyTransition(ControlSwapTransition(reduceMotion: reduceMotion))
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .notDownloaded:
            Button("Download", action: onDownload)

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 64)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Downloading")

        case .downloaded:
            Button("Use", action: onSelect)

        case .selected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .help("In use")
                .accessibilityLabel("In use")
        }
    }
}
