//
//  HomeView.swift
//  DaemonFlow
//
//  The pane the window opens on: is dictation ready, how do I use it, and
//  what did I say recently.
//

import AppKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var audioCaptureManager: AudioCaptureManager
    @EnvironmentObject private var downloadManager: ModelDownloadManager
    @EnvironmentObject private var cleanupManager: CleanupModelManager

    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            Section {
                StatusRow(
                    phase: phase,
                    detail: statusDetail
                )

                if let error = appState.transcriptionError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            if hasPermissionIssue {
                Section {
                    if hotkeyManager.needsAccessibilityPermission {
                        permissionIssue("Accessibility is off", detail: "Needed to paste into other apps.") {
                            hotkeyManager.openAccessibilitySettings()
                        }
                    }
                    if hotkeyManager.needsInputMonitoringPermission {
                        permissionIssue("Input Monitoring is off", detail: "Needed to notice the fn key.") {
                            hotkeyManager.openInputMonitoringSettings()
                        }
                    }
                    if !audioCaptureManager.micPermissionGranted {
                        permissionIssue("Microphone is off", detail: "Needed to hear you.") {
                            audioCaptureManager.openMicrophoneSettings()
                        }
                    }
                }
            }

            Section("Shortcuts") {
                shortcut("Dictate", hint: "hold", keys: ["fn"])
                shortcut("Hands-free dictation", hint: "double-tap", keys: ["fn"])
                shortcut("Clean up selected text", hint: "press", keys: ["⌥", "1"])
                shortcut("Rewrite selection by voice", hint: "hold and speak", keys: ["⌥", "1"])
            }

            Section {
                if appState.transcriptHistory.isEmpty {
                    Text("Your dictations will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.transcriptHistory) { entry in
                        TranscriptRow(entry: entry)
                    }
                }
            } header: {
                HStack {
                    Text("History")
                    Spacer()
                    if !appState.transcriptHistory.isEmpty {
                        Button("Clear…") { isConfirmingClear = true }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear all transcripts?",
            isPresented: $isConfirmingClear
        ) {
            Button("Clear History", role: .destructive) {
                appState.clearTranscriptHistory()
            }
        } message: {
            Text("This removes every saved dictation. It can't be undone.")
        }
    }

    // MARK: - Status

    private var hasPermissionIssue: Bool {
        hotkeyManager.needsAccessibilityPermission
            || hotkeyManager.needsInputMonitoringPermission
            || !audioCaptureManager.micPermissionGranted
    }

    private var phase: StatusRow.Phase {
        if hasPermissionIssue { return .blocked }
        if hotkeyManager.isRecording { return .listening(handsFree: hotkeyManager.isHandsFreeMode) }
        if appState.isTranscribing { return .transcribing }
        return .ready
    }

    private var statusDetail: String {
        let transcription = transcriptionModelName ?? "No transcription model"
        let cleanup = cleanupModelName ?? "no cleanup model"
        return "\(transcription) · \(cleanup)"
    }

    private var transcriptionModelName: String? {
        switch downloadManager.selectedEngine {
        case .parakeet:
            return ParakeetModelCatalog.defaultModel.displayName
        case .whisper:
            guard let fileName = downloadManager.selectedFileName else { return nil }
            return WhisperModelCatalog.all.first(where: { $0.fileName == fileName })?.displayName ?? fileName
        }
    }

    private var cleanupModelName: String? {
        guard let repoID = cleanupManager.selectedHubRepoID else { return nil }
        return CleanupModelCatalog.model(forHubRepoID: repoID)?.displayName ?? repoID
    }

    // MARK: - Rows

    private func permissionIssue(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: action)
        }
    }

    private func shortcut(_ title: String, hint: String, keys: [String]) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 3) {
                    ForEach(keys, id: \.self) { KeyCap($0) }
                }
            }
        }
    }
}

// MARK: - Status row

private struct StatusRow: View {
    enum Phase: Equatable {
        case ready
        case listening(handsFree: Bool)
        case transcribing
        case blocked
    }

    let phase: Phase
    let detail: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                glyph
                    .id(glyphKey)
                    .transition(IconSwapTransition(reduceMotion: reduceMotion))
            }
            .frame(width: 32, height: 32)
            .background(glyphBackground, in: Circle())
            .animation(Motion.iconSwap, value: glyphKey)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var glyphKey: String {
        switch phase {
        case .ready: "ready"
        case .listening: "listening"
        case .transcribing: "transcribing"
        case .blocked: "blocked"
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch phase {
        case .ready:
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tint)
        case .listening:
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
        case .transcribing:
            ProgressView()
                .controlSize(.small)
        case .blocked:
            Image(systemName: "exclamationmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var glyphBackground: AnyShapeStyle {
        switch phase {
        case .ready, .transcribing: AnyShapeStyle(.tint.opacity(0.14))
        case .listening: AnyShapeStyle(Color.red)
        case .blocked: AnyShapeStyle(Color.yellow)
        }
    }

    private var title: String {
        switch phase {
        case .ready: "Ready"
        case .listening(let handsFree): handsFree ? "Listening — hands-free" : "Listening"
        case .transcribing: "Transcribing"
        case .blocked: "Needs permissions"
        }
    }

    private var subtitle: String {
        switch phase {
        case .ready: "Hold fn in any app and speak. Let go to paste."
        case .listening(let handsFree): handsFree ? "Press fn again to stop." : "Release fn to paste."
        case .transcribing: "Turning your speech into text…"
        case .blocked: "Turn on the permissions below to start dictating."
        }
    }
}

// MARK: - Transcript row

/// Cleaned text first — that's what got pasted. The raw transcript sits
/// under it in tertiary ink when cleanup changed something, so it's there
/// for comparison without competing.
private struct TranscriptRow: View {
    let entry: TranscriptEntry

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if entry.hasDistinctRawText {
                    Text(entry.rawText)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .help("Heard before cleanup: \(entry.rawText)")
                }

                Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Revealed on hover without animation: row hovers happen far
            // too often for motion to be anything but noise.
            CopyButton(text: entry.text)
                .opacity(isHovering ? 1 : 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Copy") { copy(entry.text) }
            if entry.hasDistinctRawText {
                Button("Copy Original") { copy(entry.rawText) }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
