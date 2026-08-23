//
//  OnboardingView.swift
//  DaemonFlow
//

import SwiftUI

enum OnboardingMode {
    /// First launch: step 1 (Whisper) then step 2 (cleanup LLM).
    case fullFlow
    /// "Change Model" sheet — Whisper grid only.
    case whisperOnly
    /// "Change Cleanup Model" sheet — cleanup grid only.
    case cleanupOnly
}

struct OnboardingView: View {
    let mode: OnboardingMode
    var onClose: (() -> Void)?

    @State private var step: Int

    @EnvironmentObject private var downloadManager: ModelDownloadManager
    @EnvironmentObject private var cleanupManager: CleanupModelManager

    init(mode: OnboardingMode = .fullFlow, onClose: (() -> Void)? = nil) {
        self.mode = mode
        self.onClose = onClose
        _step = State(initialValue: mode == .cleanupOnly ? 2 : 1)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                LazyVGrid(columns: columns, spacing: 20) {
                    if step == 1 {
                        ForEach(WhisperModelCatalog.all) { model in
                            WhisperModelCard(model: model)
                        }
                        ForEach(ParakeetModelCatalog.all) { model in
                            ParakeetModelCard(model: model)
                        }
                    } else {
                        ForEach(CleanupModelCatalog.all) { model in
                            CleanupModelCard(model: model)
                        }
                    }
                }

                if mode == .fullFlow && step == 1 {
                    continueBar
                }
            }
            .frame(maxWidth: 760)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if mode == .fullFlow {
                    Text("STEP \(step) OF 2")
                        .font(Theme.Font.monoLabel)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }

                Text(step == 1 ? "Choose your model" : "Choose your cleanup model")
                    .font(Theme.Font.headerTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text(step == 1
                     ? "Transcribes your speech locally — Whisper or Parakeet. You can change this anytime from Settings."
                     : "Polishes raw transcripts — removes fillers, applies self-corrections. Change anytime from Settings.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.cardSurface, in: Circle())
                        .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var continueBar: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    step = 2
                }
            } label: {
                Text("Continue")
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(transcriptionModelSelected ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 22)
                    .frame(height: 34)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(transcriptionModelSelected ? Theme.accent.opacity(0.16) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(transcriptionModelSelected ? Theme.accent : Theme.cardBorder, lineWidth: 1)
            )
            .disabled(!transcriptionModelSelected)
        }
    }

    private var transcriptionModelSelected: Bool {
        downloadManager.hasUsableTranscriptionModel
    }
}

// MARK: - Catalog-specific wrappers

private struct WhisperModelCard: View {
    let model: WhisperModel
    @EnvironmentObject private var downloadManager: ModelDownloadManager

    var body: some View {
        ModelSelectionCard(
            title: model.displayName,
            tagline: model.tagline,
            stats: [
                ModelStat(label: "SIZE", value: model.sizeDescription),
                ModelStat(label: "SPEED", value: model.speedDescription),
                ModelStat(label: "ACCURACY", value: model.accuracyDescription),
            ],
            recommended: model.recommended,
            status: status,
            errorText: downloadManager.errorByModelID[model.id],
            downloadAction: { downloadManager.downloadModel(model) },
            selectAction: { downloadManager.selectModel(model) }
        )
    }

    private var status: ModelCardStatus {
        if downloadManager.isSelected(model) { return .selected }
        if downloadManager.downloadingModelIDs.contains(model.id) {
            return .downloading(progress: downloadManager.progressByModelID[model.id] ?? 0)
        }
        if downloadManager.isModelDownloaded(model) { return .downloaded }
        return .notDownloaded
    }
}

private struct ParakeetModelCard: View {
    let model: ParakeetModel
    @EnvironmentObject private var downloadManager: ModelDownloadManager

    var body: some View {
        ModelSelectionCard(
            title: model.displayName,
            tagline: model.tagline,
            stats: [
                ModelStat(label: "SIZE", value: model.sizeDescription),
                ModelStat(label: "SPEED", value: model.speedDescription),
                ModelStat(label: "ACCURACY", value: model.accuracyDescription),
            ],
            recommended: model.recommended,
            status: status,
            errorText: downloadManager.errorByModelID[model.id],
            downloadAction: { downloadManager.downloadModel(model) },
            selectAction: { downloadManager.selectModel(model) }
        )
    }

    private var status: ModelCardStatus {
        if downloadManager.isSelected(model) { return .selected }
        if downloadManager.downloadingModelIDs.contains(model.id) {
            return .downloading(progress: downloadManager.progressByModelID[model.id] ?? 0)
        }
        if downloadManager.isModelDownloaded(model) { return .downloaded }
        return .notDownloaded
    }
}

private struct CleanupModelCard: View {
    let model: CleanupModel
    @EnvironmentObject private var cleanupManager: CleanupModelManager

    var body: some View {
        ModelSelectionCard(
            title: model.displayName,
            tagline: model.tagline,
            stats: [
                ModelStat(label: "SIZE", value: model.sizeDescription),
                ModelStat(label: "SPEED", value: model.speedDescription),
                ModelStat(label: "QUALITY", value: model.qualityDescription),
            ],
            recommended: model.recommended,
            status: status,
            errorText: cleanupManager.errorByModelID[model.id],
            downloadAction: { cleanupManager.downloadAndSelect(model) },
            selectAction: { cleanupManager.selectModel(model) }
        )
    }

    private var status: ModelCardStatus {
        if cleanupManager.isSelected(model) { return .selected }
        if cleanupManager.downloadingModelIDs.contains(model.id) {
            return .downloading(progress: cleanupManager.progressByModelID[model.id] ?? 0)
        }
        if cleanupManager.isModelDownloaded(model) { return .downloaded }
        return .notDownloaded
    }
}

// MARK: - Generic model card

struct ModelStat: Identifiable {
    var id: String { label }
    let label: String
    let value: String
}

enum ModelCardStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case selected
}

struct ModelSelectionCard: View {
    let title: String
    let tagline: String
    let stats: [ModelStat]
    let recommended: Bool
    let status: ModelCardStatus
    let errorText: String?
    let downloadAction: () -> Void
    let selectAction: () -> Void

    @State private var isHovering = false

    private var isSelected: Bool { status == .selected }

    private var borderColor: Color {
        if isSelected { return Theme.accent }
        if isHovering { return Theme.textSecondary.opacity(0.45) }
        return Theme.cardBorder
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if recommended {
                RecommendedWaveform()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    if recommended {
                        RecommendedBadge()
                    }
                    Spacer()
                }

                Text(tagline)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stats) { stat in
                        HStack(spacing: 10) {
                            Text(stat.label)
                                .font(Theme.Font.monoLabel)
                                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                .frame(width: 60, alignment: .leading)
                            Text(stat.value)
                                .font(Theme.Font.mono)
                                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                            Spacer()
                        }
                    }
                }

                Spacer(minLength: 4)

                actionArea

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, recommended ? 32 : 18)
        }
        .frame(maxWidth: .infinity, minHeight: 216, alignment: .top)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(
            color: (recommended && !isSelected) ? Theme.accent.opacity(0.22) : .clear,
            radius: 24, x: 0, y: 10
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch status {
        case .selected:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.successGreen)
                Text("Selected")
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .frame(height: 32)

        case .downloading(let progress):
            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.cardBorder)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(3, geometry.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 4)

                Text("\(Int(progress * 100))%")
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .frame(height: 32)

        case .downloaded:
            Button(action: selectAction) {
                Text("Select")
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
            .background(Theme.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .notDownloaded:
            Button(action: downloadAction) {
                Text("Download & Select")
                    .font(Theme.Font.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(DownloadButtonStyle())
        }
    }
}

/// Transparent by default, subtle accent fill on hover/press — matches
/// the "no bounce, opacity/border transitions only" motion rule.
private struct DownloadButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.18 : (isHovering ? 0.1 : 0)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.accent, lineWidth: 1)
            )
            .onHover { hovering in isHovering = hovering }
            .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Recommended badge & waveform

private struct RecommendedBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 1 : 0.35)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            Text("RECOMMENDED")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.accent)
        }
        .onAppear { pulse = true }
    }
}

/// The one deliberate motion moment on this screen: a thin, quiet
/// waveform along the recommended card's bottom edge.
private struct RecommendedWaveform: View {
    @State private var animate = false

    private let baseHeights: [CGFloat] = [5, 9, 13, 8, 11, 6]

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(baseHeights.enumerated()), id: \.offset) { index, base in
                Capsule()
                    .fill(Theme.accent.opacity(0.4))
                    .frame(width: 3, height: animate ? base : base * 0.4)
                    .animation(
                        .easeInOut(duration: 0.9)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.12),
                        value: animate
                    )
            }
            Spacer()
        }
        .frame(height: 14)
        .onAppear { animate = true }
    }
}
