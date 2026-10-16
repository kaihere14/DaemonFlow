//
//  OnboardingView.swift
//  DaemonFlow
//
//  First-run setup, in three short screens sharing one layout: permissions,
//  then a transcription model, then a cleanup model. Each screen stages in
//  once (icon, heading, content) — the only place in the app with an
//  expressive entrance, because it's seen once.
//

import AVFoundation
import AppKit
import SwiftUI

// MARK: - Shared layout

struct OnboardingScaffold<Content: View, Footer: View>: View {
    /// Zero-based position in the three-screen flow.
    let step: Int
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    static var stepCount: Int { 3 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                    .staggeredEntrance(0)
                    .padding(.bottom, 14)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)
                }
                .staggeredEntrance(1)
                // A new identity per step replays the heading's entrance
                // when the flow advances, without replaying the icon's.
                .id(step)
            }
            .padding(.top, 28)
            .padding(.horizontal, 32)

            content
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .staggeredEntrance(2)
                .id(step)

            Divider()

            HStack(spacing: 12) {
                StepIndicator(current: step, count: Self.stepCount)
                Spacer()
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// Dots, with the current one stretched into a short bar. The stretch is
/// the only thing that moves when the flow advances.
private struct StepIndicator: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 16 : 6, height: 6)
            }
        }
        .animation(Motion.standard, value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: - Step 1: permissions

/// Shows all three permissions at once so it's clear how much is left.
/// There's no Continue button: AppState watches all three and the window
/// moves on by itself the moment the last one lands.
struct PermissionsOnboardingView: View {
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var audioCaptureManager: AudioCaptureManager

    var body: some View {
        OnboardingScaffold(
            step: 0,
            title: "Welcome to DaemonFlow",
            subtitle: "Hold fn, speak, and let go — your words appear wherever you're typing. First, DaemonFlow needs three permissions."
        ) {
            Form {
                Section {
                    PermissionRow(
                        systemImage: "accessibility",
                        tint: .blue,
                        title: "Accessibility",
                        detail: "Pastes your text into the app you're using.",
                        isGranted: !hotkeyManager.needsAccessibilityPermission,
                        isNext: nextStep == 0,
                        actionTitle: "Open Settings",
                        action: hotkeyManager.openAccessibilitySettings
                    )
                    PermissionRow(
                        systemImage: "keyboard",
                        tint: .gray,
                        title: "Input Monitoring",
                        detail: "Notices the fn key in every app, not just this one.",
                        isGranted: !hotkeyManager.needsInputMonitoringPermission,
                        isNext: nextStep == 1,
                        actionTitle: "Open Settings",
                        action: hotkeyManager.openInputMonitoringSettings
                    )
                    PermissionRow(
                        systemImage: "mic.fill",
                        tint: .orange,
                        title: "Microphone",
                        detail: "Hears you while fn is held.",
                        isGranted: audioCaptureManager.micPermissionGranted,
                        isNext: nextStep == 2,
                        actionTitle: micNeedsPrompt ? "Allow" : "Open Settings",
                        action: requestMicrophone
                    )
                } footer: {
                    Text("Everything runs on this Mac. Audio and text never leave it.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } footer: {
            Text("Continues on its own once all three are on.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Check Again") {
                hotkeyManager.retryEventTap()
                audioCaptureManager.recheckMicPermission()
            }
        }
    }

    /// The first permission still off — the one whose button is
    /// prominent, so there's always exactly one obvious next click.
    private var nextStep: Int? {
        if hotkeyManager.needsAccessibilityPermission { return 0 }
        if hotkeyManager.needsInputMonitoringPermission { return 1 }
        if !audioCaptureManager.micPermissionGranted { return 2 }
        return nil
    }

    private var micNeedsPrompt: Bool {
        audioCaptureManager.micAuthorizationStatus == .notDetermined
    }

    /// The microphone can be asked for in place the first time. After a
    /// refusal macOS won't ask again, so it's System Settings from then on.
    private func requestMicrophone() {
        if micNeedsPrompt {
            audioCaptureManager.requestMicPermission()
        } else {
            audioCaptureManager.openMicrophoneSettings()
        }
    }
}

private struct PermissionRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String
    let isGranted: Bool
    let isNext: Bool
    let actionTitle: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            SettingsGlyph(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            ZStack(alignment: .trailing) {
                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Allowed")
                        .transition(IconSwapTransition(reduceMotion: reduceMotion))
                } else if isNext {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .transition(ControlSwapTransition(reduceMotion: reduceMotion))
                } else {
                    Button(actionTitle, action: action)
                        .transition(ControlSwapTransition(reduceMotion: reduceMotion))
                }
            }
            .animation(Motion.iconSwap, value: isGranted)
            .animation(Motion.iconSwap, value: isNext)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Steps 2 and 3: models

struct OnboardingView: View {
    @EnvironmentObject private var downloadManager: ModelDownloadManager
    @EnvironmentObject private var cleanupManager: CleanupModelManager

    private enum Step {
        case transcription, cleanup
    }

    @State private var step: Step = .transcription

    var body: some View {
        OnboardingScaffold(
            step: step == .transcription ? 1 : 2,
            title: step == .transcription ? "Choose a speech model" : "Choose a cleanup model",
            subtitle: step == .transcription
                ? "This turns your voice into text, on this Mac. The recommended one suits most people — you can change it any time."
                : "This tidies the raw transcript — filler words out, corrections applied, punctuation in — before it's pasted."
        ) {
            Form {
                Section {
                    switch step {
                    case .transcription: TranscriptionModelList()
                    case .cleanup: CleanupModelList()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } footer: {
            switch step {
            case .transcription:
                Button("Continue") { step = .cleanup }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!downloadManager.hasUsableTranscriptionModel)
            case .cleanup:
                // Picking a cleanup model completes setup, and the window
                // switches over to settings by itself.
                Text("Setup finishes once a model is ready.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Back") { step = .transcription }
            }
        }
    }
}
