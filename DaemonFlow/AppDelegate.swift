//
//  AppDelegate.swift
//  DaemonFlow
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appNapActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Without this, macOS App-Naps the process once the last window
        // closes, throttling the run loop that services the CGEventTap —
        // the Fn hotkey (and everything downstream) goes dead until a
        // window is visible again. AllowingIdleSystemSleep keeps the Mac
        // itself free to sleep normally.
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Global Fn hotkey monitoring and dictation"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
