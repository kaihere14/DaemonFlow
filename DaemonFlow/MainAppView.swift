//
//  MainAppView.swift
//  DaemonFlow
//

import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var audioCaptureManager: AudioCaptureManager
    @EnvironmentObject private var vocabularyStore: VocabularyStore
    @EnvironmentObject private var hudSettings: HUDSettingsStore
    @EnvironmentObject private var promptStore: PromptStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("DaemonFlow")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            hotkeyStatusCard
            modelStatusCard
            transcriptCard
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .sheet(isPresented: $appState.isPresentingModelPicker) {
            OnboardingView(mode: .whisperOnly, onClose: { appState.isPresentingModelPicker = false })
                .frame(minWidth: 680, minHeight: 560)
        }
        .sheet(isPresented: $appState.isPresentingCleanupPicker) {
            OnboardingView(mode: .cleanupOnly, onClose: { appState.isPresentingCleanupPicker = false })
                .frame(minWidth: 680, minHeight: 560)
        }
        .sheet(isPresented: $appState.isPresentingCleanupLab) {
            DebugCleanupView(onClose: { appState.isPresentingCleanupLab = false })
                .frame(minWidth: 600, minHeight: 520)
        }
        .sheet(isPresented: $appState.isPresentingHUDAppearance) {
            HUDAppearanceView(onClose: { appState.isPresentingHUDAppearance = false })
                .frame(minWidth: 560, minHeight: 620)
        }
        .sheet(isPresented: $appState.isPresentingPrompts) {
            PromptsView(onClose: { appState.isPresentingPrompts = false })
                .frame(minWidth: 620, minHeight: 620)
        }
        .sheet(isPresented: $appState.isPresentingVocabulary) {
            VocabularyView(onClose: { appState.isPresentingVocabulary = false })
                .frame(minWidth: 560, minHeight: 480)
        }
    }

    private var hotkeyStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkey status")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Label(
                hotkeyManager.isRecording ? "Recording" : "Idle",
                systemImage: hotkeyManager.isRecording ? "waveform.circle.fill" : "waveform.circle"
            )
            .font(.system(size: 13))
            .foregroundStyle(hotkeyManager.isRecording ? .red : Theme.textSecondary)

            if hotkeyManager.isHandsFreeMode {
                Text("Hands-free mode is active")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Hold Fn and speak to dictate.")
                Text("Select text, then tap ⌥1 to clean it up — or hold ⌥1 and say how to change it (\u{201C}make it formal\u{201D}).")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if hotkeyManager.needsAccessibilityPermission {
                Text("Accessibility permission not granted")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if hotkeyManager.needsInputMonitoringPermission {
                Text("Input Monitoring permission not granted")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if !audioCaptureManager.micPermissionGranted {
                HStack(spacing: 8) {
                    Text("Microphone access not granted")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Button("Open Microphone Settings") {
                        audioCaptureManager.openMicrophoneSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private var modelStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            modelRow(
                title: "Transcription model",
                value: appState.modelDownloadManager.selectedModelDisplayName ?? "None selected",
                buttonTitle: "Change Model"
            ) {
                appState.isPresentingModelPicker = true
            }

            Divider().overlay(Theme.cardBorder)

            modelRow(
                title: "Cleanup model",
                value: cleanupModelLabel,
                buttonTitle: "Change Cleanup Model"
            ) {
                appState.isPresentingCleanupPicker = true
            }

            Divider().overlay(Theme.cardBorder)

            modelRow(
                title: "Custom vocabulary",
                value: vocabularyLabel,
                buttonTitle: "Edit Dictionary"
            ) {
                appState.isPresentingVocabulary = true
            }

            Divider().overlay(Theme.cardBorder)

            toggleRow(
                title: "Always show the pill",
                subtitle: "Keeps a thin bar above the Dock between dictations. It grows into the waveform when you start speaking.",
                isOn: $hudSettings.alwaysVisible
            )

            Divider().overlay(Theme.cardBorder)

            modelRow(
                title: "Pill appearance",
                value: pillSizeLabel,
                buttonTitle: "Customize"
            ) {
                appState.isPresentingHUDAppearance = true
            }

            Divider().overlay(Theme.cardBorder)

            modelRow(
                title: "Prompts",
                value: promptsLabel,
                buttonTitle: "Edit Prompts"
            ) {
                appState.isPresentingPrompts = true
            }

            HStack {
                Spacer()
                Button("Test Cleanup") {
                    appState.isPresentingCleanupLab = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func modelRow(
        title: String,
        value: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.accent, lineWidth: 1)
                )
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
        }
    }

    private var cleanupModelLabel: String {
        guard let repoID = appState.cleanupModelManager.selectedHubRepoID else {
            return "None selected"
        }
        return CleanupModelCatalog.model(forHubRepoID: repoID)?.displayName ?? repoID
    }

    private var pillSizeLabel: String {
        let appearance = hudSettings.appearance
        return "\(Int(appearance.restingWidth))×\(Int(appearance.restingHeight)) resting · "
            + "\(Int(appearance.activeWidth))×\(Int(appearance.activeHeight)) active"
    }

    private var promptsLabel: String {
        // Reading `revision` keeps this label live: the counts come out of
        // UserDefaults, which doesn't publish on its own.
        _ = promptStore.revision
        let edited = promptStore.customizedCount
        switch edited {
        case 0: return "\(PromptKind.allCases.count) prompts · all default"
        case 1: return "\(PromptKind.allCases.count) prompts · 1 edited"
        default: return "\(PromptKind.allCases.count) prompts · \(edited) edited"
        }
    }

    private var vocabularyLabel: String {
        let count = vocabularyStore.terms.count
        switch count {
        case 0: return "No custom terms"
        case 1: return "1 term"
        default: return "\(count) terms"
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Transcripts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if appState.isTranscribing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                if !appState.transcriptHistory.isEmpty {
                    Button("Clear") {
                        appState.clearTranscriptHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            if let error = appState.transcriptionError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if appState.transcriptHistory.isEmpty {
                Text("Hold Fn and speak — transcripts will appear here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.transcriptHistory) { entry in
                            transcriptRow(entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    /// Cleaned text on top (that's what got pasted), the untouched Whisper
    /// output indented beneath it behind a "RAW" rule — visible without a
    /// click, but clearly subordinate. Omitted entirely when cleanup didn't
    /// change anything, since two identical blocks would just be noise.
    private func transcriptRow(_ entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(Theme.Font.monoLabel)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))

            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.hasDistinctRawText {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(Theme.cardBorder)
                        .frame(width: 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RAW")
                            .font(Theme.Font.monoLabel)
                            .foregroundStyle(Theme.textSecondary.opacity(0.55))
                        Text(entry.rawText)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 4)
    }
}

#Preview {
    let appState = AppState()
    return MainAppView()
        .environmentObject(appState)
        .environmentObject(appState.hotkeyManager)
        .environmentObject(appState.audioCaptureManager)
        .environmentObject(appState.vocabularyStore)
        .environmentObject(appState.hudSettings)
}
