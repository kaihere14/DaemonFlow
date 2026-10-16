//
//  MenuBarView.swift
//  DaemonFlow
//
//  A plain system menu. It's opened dozens of times a day, so it gets the
//  instant, unanimated NSMenu every other status item uses rather than a
//  custom popover.
//

import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var audioCaptureManager: AudioCaptureManager

    var body: some View {
        Text(statusTitle)

        if needsPermissions {
            Button("Finish Setup…", action: openMainWindow)
        }

        Divider()

        if let last = appState.transcriptHistory.first {
            Button("Copy Last Transcript") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(last.text, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()
        }

        Button("Open DaemonFlow…", action: openMainWindow)
            .keyboardShortcut(",")

        Divider()

        Button("Quit DaemonFlow") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var needsPermissions: Bool {
        hotkeyManager.needsAccessibilityPermission
            || hotkeyManager.needsInputMonitoringPermission
            || !audioCaptureManager.micPermissionGranted
    }

    private var statusTitle: String {
        if needsPermissions { return "Permissions needed" }
        if hotkeyManager.isRecording {
            return hotkeyManager.isHandsFreeMode ? "Listening — hands-free" : "Listening…"
        }
        if appState.isTranscribing { return "Transcribing…" }
        return "Ready — hold fn to dictate"
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
