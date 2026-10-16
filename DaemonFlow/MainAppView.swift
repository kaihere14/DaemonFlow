//
//  MainAppView.swift
//  DaemonFlow
//
//  Window root: routes between permission setup, model setup and the
//  settings window itself, which is laid out the way System Settings is —
//  a sidebar of panes, each one a grouped form.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    private enum Route: Equatable {
        case permissions, models, main
    }

    private var route: Route {
        if !appState.hasRequiredPermissions { return .permissions }
        if !appState.hasCompletedOnboarding { return .models }
        return .main
    }

    var body: some View {
        ZStack {
            switch route {
            case .permissions:
                PermissionsOnboardingView()
                    .transition(.opacity)
            case .models:
                OnboardingView()
                    .transition(.opacity)
            case .main:
                MainAppView()
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .animation(Motion.standard, value: route)
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case home
    case models
    case vocabulary
    case prompts
    case pill
    case playground

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .models: "Models"
        case .vocabulary: "Vocabulary"
        case .prompts: "Prompts"
        case .pill: "Pill"
        case .playground: "Playground"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .models: "cpu"
        case .vocabulary: "character.book.closed"
        case .prompts: "text.quote"
        case .pill: "capsule"
        case .playground: "flask"
        }
    }
}

struct MainAppView: View {
    @SceneStorage("selectedPane") private var pane: Pane = .home

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    row(.home)
                }
                Section("Settings") {
                    row(.models)
                    row(.vocabulary)
                    row(.prompts)
                    row(.pill)
                }
                Section("Tools") {
                    row(.playground)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            // Switching panes is instant — it happens constantly, and an
            // animation there would only make the window feel slower.
            detail
                .navigationTitle(pane.title)
        }
    }

    /// The sidebar wants an optional selection; mapping nil back to the
    /// current pane means a stray click on empty space can't leave the
    /// window with nothing selected.
    private var selection: Binding<Pane?> {
        Binding(
            get: { pane },
            set: { if let newValue = $0 { pane = newValue } }
        )
    }

    private func row(_ pane: Pane) -> some View {
        Label(pane.title, systemImage: pane.systemImage)
            .tag(pane)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .home: HomeView()
        case .models: ModelsView()
        case .vocabulary: VocabularyView()
        case .prompts: PromptsView()
        case .pill: HUDAppearanceView()
        case .playground: DebugCleanupView()
        }
    }
}
