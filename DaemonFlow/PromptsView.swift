//
//  PromptsView.swift
//  DaemonFlow
//
//  Editor for the three system prompts the cleanup model runs on. Each one
//  is saved separately and read back at call time, so an edit applies to
//  the next dictation or refine without relaunching the app.
//

import SwiftUI

struct PromptsView: View {
    @EnvironmentObject private var store: PromptStore

    @SceneStorage("selectedPrompt") private var kind: PromptKind = .dictationCleanup

    /// Working copies, one per prompt. Edits stay here until Save, so
    /// switching to another prompt mid-edit doesn't lose anything.
    @State private var drafts: [PromptKind: String] = [:]

    var body: some View {
        Form {
            Section {
                Picker("Prompt", selection: $kind) {
                    ForEach(PromptKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } footer: {
                Text(kind.subtitle)
            }

            Section {
                TextEditor(text: binding(for: kind))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 280)
            } header: {
                HStack {
                    Text("Instructions")
                    Spacer()
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(hasUnsavedChanges ? .orange : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Reset to Default") {
                    store.reset(kind)
                    drafts[kind] = kind.defaultText
                }
                .disabled(draft(for: kind) == kind.defaultText && !store.isCustomized(kind))
                .help("Replace this prompt with the one DaemonFlow ships with")

                Button("Save") {
                    store.save(draft(for: kind), for: kind)
                    drafts[kind] = store.text(for: kind)
                }
                .keyboardShortcut("s")
                .disabled(!hasUnsavedChanges)
            }
        }
        .onAppear(perform: loadDrafts)
    }

    private var hasUnsavedChanges: Bool {
        draft(for: kind) != store.text(for: kind)
    }

    private var statusLabel: String {
        // Reading `revision` keeps this live: the values come out of
        // UserDefaults, which doesn't publish on its own.
        _ = store.revision
        if hasUnsavedChanges { return "Unsaved changes" }
        return store.isCustomized(kind) ? "Edited" : "Default"
    }

    // MARK: - Drafts

    private func loadDrafts() {
        for kind in PromptKind.allCases where drafts[kind] == nil {
            drafts[kind] = store.text(for: kind)
        }
    }

    private func draft(for kind: PromptKind) -> String {
        drafts[kind] ?? store.text(for: kind)
    }

    private func binding(for kind: PromptKind) -> Binding<String> {
        Binding(
            get: { draft(for: kind) },
            set: { drafts[kind] = $0 }
        )
    }
}
