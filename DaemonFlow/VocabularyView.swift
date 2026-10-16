//
//  VocabularyView.swift
//  DaemonFlow
//
//  Editor for the custom dictionary: names, product terms and jargon the
//  speech model has never been trained on. Anything close enough to an
//  entry gets rewritten to the exact spelling typed here.
//

import SwiftUI

struct VocabularyView: View {
    @EnvironmentObject private var store: VocabularyStore

    @State private var newTerm = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    TextField("New term", text: $newTerm, prompt: Text("Add a name or term…"))
                        .labelsHidden()
                        .focused($addFieldFocused)
                        .onSubmit(commitNewTerm)

                    Button("Add", action: commitNewTerm)
                        .disabled(!canAdd)
                }
            } footer: {
                // Worth stating up front — a user who adds "Wave" and sees
                // nothing change would otherwise assume the feature is broken.
                Text("Words the speech model gets wrong are rewritten to the spelling you add here. Terms of four letters or fewer only have their capitalization fixed.")
            }

            Section {
                Toggle("Use text on screen", isOn: $store.usesScreenContext)
            } footer: {
                Text("While you dictate, unusual names and terms in the frontmost window — like \"Supabase\" in the doc you're editing — are used to fix how they're spelled. Password fields are never read, and nothing leaves your Mac.")
            }

            Section {
                if store.terms.isEmpty {
                    Text("Add the spellings you keep fixing by hand.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.terms) { term in
                        HStack(spacing: 8) {
                            EditableTermField(term: term) { store.update(term.id, to: $0) }
                            IconButton(systemImage: "minus.circle", help: "Remove \(term.text)") {
                                store.remove(term.id)
                            }
                        }
                    }
                }
            } header: {
                Text(termCountLabel)
            }
        }
        .formStyle(.grouped)
        .onAppear { addFieldFocused = true }
    }

    private var termCountLabel: String {
        switch store.terms.count {
        case 0: "Terms"
        case 1: "1 term"
        default: "\(store.terms.count) terms"
        }
    }

    private var canAdd: Bool {
        !newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Clears the field only on a successful add, so a rejected duplicate
    /// leaves the text there to be edited rather than vanishing.
    private func commitNewTerm() {
        guard canAdd else { return }
        if store.add(newTerm) {
            newTerm = ""
        }
        addFieldFocused = true
    }
}

/// Each row edits its own local copy and commits on blur or Return.
/// Binding straight through to the store would rewrite the file on every
/// keystroke — and delete the row the moment the field was emptied to
/// retype it.
private struct EditableTermField: View {
    let term: VocabularyTerm
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(term: VocabularyTerm, onCommit: @escaping (String) -> Void) {
        self.term = term
        self.onCommit = onCommit
        _draft = State(initialValue: term.text)
    }

    var body: some View {
        TextField("Term", text: $draft)
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($focused)
            .onSubmit { onCommit(draft) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { onCommit(draft) }
            }
            .onChange(of: term.text) { _, newValue in
                if !focused { draft = newValue }
            }
    }
}
