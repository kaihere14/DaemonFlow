//
//  DaemonFlowApp.swift
//  DaemonFlow
//
//  Created by Arman Thakur on 7/29/26.
//

import AppKit
import SwiftUI

@main
struct DaemonFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(appState.hotkeyManager)
                .environmentObject(appState.audioCaptureManager)
        } label: {
            // The label is rendered immediately at launch regardless of
            // whether the popover is ever opened — this is the one place
            // guaranteed to fire once at startup, which is what lets us
            // force the setup window open without the user having to find
            // and click the menu bar icon themselves first.
            Image(systemName: "waveform")
                .onAppear { openSetupWindowIfNeeded() }
        }
        .menuBarExtraStyle(.window)

        Window("DaemonFlow Settings", id: "main") {
            Group {
                if !appState.hasRequiredPermissions {
                    PermissionsOnboardingView()
                } else if appState.hasCompletedOnboarding {
                    MainAppView()
                } else {
                    OnboardingView(mode: .fullFlow)
                }
            }
            .frame(minWidth: 640, minHeight: 480)
            .environmentObject(appState)
            .environmentObject(appState.hotkeyManager)
            .environmentObject(appState.modelDownloadManager)
            .environmentObject(appState.cleanupModelManager)
            .environmentObject(appState.audioCaptureManager)
            .environmentObject(appState.vocabularyStore)
            .environmentObject(appState.hudSettings)
            .environmentObject(appState.promptStore)
        }
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentMinSize)
    }

    /// Auto-opens and foregrounds the setup window at launch whenever
    /// permissions or model onboarding still need attention — so a fresh
    /// install (or a permission wiped by a rebuild) doesn't leave the user
    /// staring at a menu bar icon with no idea anything needs doing. Once
    /// setup is fully complete, launches stay silent in the menu bar as
    /// intended.
    private func openSetupWindowIfNeeded() {
        guard !appState.hasRequiredPermissions || !appState.hasCompletedOnboarding else { return }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
