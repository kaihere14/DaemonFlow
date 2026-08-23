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
    var onClose: (() -> Void)?

    @EnvironmentObject private var store: VocabularyStore

    @State private var newTerm = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            addRow
            list
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .onAppear { addFieldFocused = true }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom vocabulary")
                    .font(Theme.Font.headerTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Names and terms the speech model gets wrong. Anything it hears that's close to an entry is rewritten to the spelling you type here.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.cardSurface, in: Circle())
                        .overlay(Circle().stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("DaemonFlow, Whisper Flow, Anthropic…", text: $newTerm)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($addFieldFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.cardSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.cardBorder, lineWidth: 1)
                    )
                    .onSubmit(commitNewTerm)

                Button("Add", action: commitNewTerm)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(canAdd ? Theme.accent : Theme.textSecondary.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(canAdd ? Theme.accent : Theme.cardBorder, lineWidth: 1)
                    )
                    .disabled(!canAdd)
            }

            // Worth stating up front — a user who adds "Wave" and sees
            // nothing change would otherwise assume the feature is broken.
            Text("Terms of four characters or fewer are only corrected for capitalization. Fuzzy matching that short would rewrite ordinary words.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var list: some View {
        if store.terms.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No terms yet")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add the spellings you keep having to fix by hand.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.terms) { term in
                        termRow(term)
                        if term.id != store.terms.last?.id {
                            Divider().overlay(Theme.cardBorder)
                        }
                    }
                }
            }
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
        }
    }

    private func termRow(_ term: VocabularyTerm) -> some View {
        HStack(spacing: 10) {
            EditableTermField(term: term) { store.update(term.id, to: $0) }

            Button {
                store.remove(term.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.Font.mono)
            .foregroundStyle(Theme.textPrimary)
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
