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
    var onClose: (() -> Void)?

    @EnvironmentObject private var store: PromptStore

    /// Working copies. Edits stay here until Save, so backing out of a
    /// half-written prompt is just closing the sheet.
    @State private var drafts: [PromptKind: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(PromptKind.allCases) { kind in
                        promptCard(kind)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .onAppear(perform: loadDrafts)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Prompts")
                    .font(Theme.Font.headerTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("The instructions sent to the cleanup model, one per action. Saved edits apply to the next dictation or refine — no restart needed.")
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

    private func promptCard(_ kind: PromptKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(kind.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if store.isCustomized(kind) {
                    Text("Edited")
                        .font(Theme.Font.monoLabel)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(
                            Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1)
                        )
                }
            }

            TextEditor(text: binding(for: kind))
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 220)
                .background(Theme.cardSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

            HStack(spacing: 10) {
                Text(unsavedChanges(kind) ? "Unsaved changes" : "Saved")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(unsavedChanges(kind) ? 1 : 0.6))

                Spacer()

                actionButton(
                    "Reset to Default",
                    enabled: draft(for: kind) != kind.defaultText || store.isCustomized(kind)
                ) {
                    store.reset(kind)
                    drafts[kind] = kind.defaultText
                }

                actionButton("Save", enabled: unsavedChanges(kind), prominent: true) {
                    store.save(draft(for: kind), for: kind)
                    drafts[kind] = store.text(for: kind)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func actionButton(
        _ title: String,
        enabled: Bool,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled
                             ? (prominent ? Theme.accent : Theme.textSecondary)
                             : Theme.textSecondary.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(enabled && prominent ? Theme.accent : Theme.cardBorder, lineWidth: 1)
            )
            .disabled(!enabled)
    }

    // MARK: - Draft state

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

    private func unsavedChanges(_ kind: PromptKind) -> Bool {
        draft(for: kind) != store.text(for: kind)
    }
}
