//
//  MenuBarView.swift
//  DaemonFlow
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var hotkeyManager: HotkeyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(hotkeyManager.isRecording ? .red : Theme.textSecondary)
                Text(hotkeyManager.isRecording ? "Recording" : "Idle")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Circle()
                    .fill(hotkeyManager.isRecording ? Color.red : Theme.textSecondary.opacity(0.4))
                    .frame(width: 8, height: 8)
            }

            if hotkeyManager.isHandsFreeMode {
                Text("Hands-free")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if hotkeyManager.needsAccessibilityPermission {
                Divider()

                Text("Accessibility permission is required for the Fn hotkey to work.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Button("Grant Accessibility Permission") {
                    hotkeyManager.openAccessibilitySettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)

                Button("Retry") {
                    hotkeyManager.retryEventTap()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
            }

            Divider()

            Button("Open DaemonFlow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(12)
        .frame(width: 240)
        .background(Theme.background)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(HotkeyManager())
}
