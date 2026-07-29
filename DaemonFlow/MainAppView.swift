//
//  MainAppView.swift
//  DaemonFlow
//

import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var audioCaptureManager: AudioCaptureManager

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
                title: "Whisper model",
                value: appState.modelDownloadManager.selectedFileName ?? "None selected",
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

    private var cleanupModelLabel: String {
        guard let repoID = appState.cleanupModelManager.selectedHubRepoID else {
            return "None selected"
        }
        return CleanupModelCatalog.model(forHubRepoID: repoID)?.displayName ?? repoID
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
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.date, style: .time)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                                Text(entry.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
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

    private var selectedModelLabel: String {
        appState.modelDownloadManager.selectedFileName ?? "None selected"
    }
}

#Preview {
    let appState = AppState()
    return MainAppView()
        .environmentObject(appState)
        .environmentObject(appState.hotkeyManager)
        .environmentObject(appState.audioCaptureManager)
}
