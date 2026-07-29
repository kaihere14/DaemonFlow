//
//  PermissionsOnboardingView.swift
//  DaemonFlow
//
//  First-run (and post-rebuild) gate: permissions the pipeline needs to
//  function at all, granted strictly one at a time, before offering model
//  downloads. Shows only the current (first ungranted) permission full
//  width; auto-advances to the next the instant the current one is
//  detected as granted — AppState.hasRequiredPermissions polls all three,
//  so no "Continue" button is needed here.
//

import AVFoundation
import SwiftUI

struct PermissionsOnboardingView: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var audioCaptureManager: AudioCaptureManager

    private var steps: [PermissionStepConfig] {
        [
            PermissionStepConfig(
                icon: "hand.raised.fill",
                title: "Accessibility",
                description: "Lets DaemonFlow paste cleaned transcripts into whatever app you're using, by simulating Cmd+V.",
                isGranted: !hotkeyManager.needsAccessibilityPermission,
                primaryActionTitle: "Open System Settings",
                primaryAction: { hotkeyManager.openAccessibilitySettings() },
                secondaryActionTitle: "I granted it — retry",
                secondaryAction: { hotkeyManager.retryEventTap() }
            ),
            PermissionStepConfig(
                icon: "keyboard.fill",
                title: "Input Monitoring",
                description: "Lets DaemonFlow detect the Fn key system-wide — this is what makes hold-to-record work in any app, not just DaemonFlow.",
                isGranted: !hotkeyManager.needsInputMonitoringPermission,
                primaryActionTitle: micLikeButtonTitle(for: .inputMonitoring),
                primaryAction: { requestOrOpenSettings(for: .inputMonitoring) },
                secondaryActionTitle: "I granted it — retry",
                secondaryAction: { hotkeyManager.retryEventTap() }
            ),
            PermissionStepConfig(
                icon: "mic.fill",
                title: "Microphone",
                description: "Lets DaemonFlow record your voice while you hold Fn.",
                isGranted: audioCaptureManager.micPermissionGranted,
                primaryActionTitle: micLikeButtonTitle(for: .microphone),
                primaryAction: { requestOrOpenSettings(for: .microphone) },
                secondaryActionTitle: "I granted it — retry",
                secondaryAction: { audioCaptureManager.recheckMicPermission() }
            ),
        ]
    }

    private var currentStepIndex: Int {
        steps.firstIndex(where: { !$0.isGranted }) ?? steps.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            PermissionCard(config: steps[currentStepIndex])
                .id(currentStepIndex)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

            progressDots

            Text("This continues automatically once every permission above is granted.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: 480)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Theme.background)
        .animation(.easeOut(duration: 0.25), value: currentStepIndex)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STEP \(currentStepIndex + 1) OF \(steps.count)")
                .font(Theme.Font.monoLabel)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))

            Text("Enable permissions")
                .font(Theme.Font.headerTitle)
                .foregroundStyle(Theme.textPrimary)

            Text("DaemonFlow needs these to work at all. Grant one, and it moves to the next.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                Circle()
                    .fill(steps[index].isGranted ? Theme.successGreen : (index == currentStepIndex ? Theme.accent : Theme.cardBorder))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private enum RequestKind { case inputMonitoring, microphone }

    private func micLikeButtonTitle(for kind: RequestKind) -> String {
        switch kind {
        case .inputMonitoring:
            return "Open System Settings"
        case .microphone:
            return audioCaptureManager.micAuthorizationStatus == .notDetermined
                ? "Grant Microphone Access"
                : "Open System Settings"
        }
    }

    /// Microphone gets an in-app system prompt on first ask (AVFoundation
    /// supports that). Input Monitoring's CGRequestListenEventAccess is
    /// unreliable across macOS versions for actually surfacing a prompt, so
    /// it always deep-links straight to System Settings.
    private func requestOrOpenSettings(for kind: RequestKind) {
        switch kind {
        case .inputMonitoring:
            hotkeyManager.openInputMonitoringSettings()
        case .microphone:
            if audioCaptureManager.micAuthorizationStatus == .notDetermined {
                audioCaptureManager.requestMicPermission()
            } else {
                audioCaptureManager.openMicrophoneSettings()
            }
        }
    }
}

private struct PermissionStepConfig {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let primaryActionTitle: String
    let primaryAction: () -> Void
    let secondaryActionTitle: String
    let secondaryAction: () -> Void
}

private struct PermissionCard: View {
    let config: PermissionStepConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: config.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(config.isGranted ? Theme.successGreen : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardSurfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(config.title)
                        .font(Theme.Font.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    statusBadge
                }

                Spacer()
            }

            Text(config.description)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !config.isGranted {
                HStack(spacing: 10) {
                    Button(config.primaryActionTitle, action: config.primaryAction)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.accent, lineWidth: 1)
                        )

                    Button(config.secondaryActionTitle, action: config.secondaryAction)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(config.isGranted ? Theme.successGreen.opacity(0.5) : Theme.cardBorder, lineWidth: 1)
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(config.isGranted ? Theme.successGreen : Theme.textSecondary.opacity(0.5))
                .frame(width: 5, height: 5)
            Text(config.isGranted ? "GRANTED" : "NOT GRANTED")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(config.isGranted ? Theme.successGreen : Theme.textSecondary)
        }
    }
}

#Preview {
    PermissionsOnboardingView()
        .environmentObject(HotkeyManager())
        .environmentObject(AudioCaptureManager())
        .frame(width: 640, height: 420)
}
