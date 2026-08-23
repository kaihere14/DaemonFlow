//
//  PromptStore.swift
//  DaemonFlow
//
//  User-editable copies of the three system prompts. The defaults live in
//  LLMCleanupEngine; anything saved here overrides them, and is read back
//  at call time so an edit lands on the next dictation without a restart.
//

import Combine
import Foundation

/// The three prompts, one per action the cleanup model performs.
enum PromptKind: String, CaseIterable, Identifiable, Sendable {
    /// Fn dictation — raw speech in, written text out.
    case dictationCleanup
    /// ⌥1 tapped — minimal in-place edit of selected written text.
    case manualRefine
    /// ⌥1 held — the same edit, steered by what the user said out loud.
    case instructedRefine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictationCleanup: "Dictation cleanup"
        case .manualRefine: "Manual refine"
        case .instructedRefine: "Instructed refine"
        }
    }

    var subtitle: String {
        switch self {
        case .dictationCleanup:
            "Runs on every Fn dictation. Turns the raw transcript into written text before it's pasted."
        case .manualRefine:
            "Runs when ⌥1 is tapped with text selected. Fixes the selection in place without changing what it says."
        case .instructedRefine:
            "Runs when ⌥1 is held and you speak an instruction (\"make it formal\"). Edits the selection the way you asked."
        }
    }

    /// The shipped prompt, used whenever nothing has been saved.
    var defaultText: String {
        switch self {
        case .dictationCleanup: LLMCleanupEngine.defaultCleanupPrompt
        case .manualRefine: LLMCleanupEngine.defaultRefinePrompt
        case .instructedRefine: LLMCleanupEngine.defaultInstructedRefinePrompt
        }
    }

    var defaultsKey: String { "prompt.\(rawValue)" }
}

/// Free functions rather than methods on the store: the cleanup engine is
/// an actor off the main thread and needs to read a prompt mid-call, which
/// it can't do through a @MainActor object. UserDefaults is thread-safe,
/// so the read is the whole implementation.
enum PromptLibrary {
    /// The prompt to actually send. Always hits UserDefaults — nothing is
    /// cached, so an edit applies to the very next cleanup or refine.
    static func text(for kind: PromptKind) -> String {
        stored(for: kind) ?? kind.defaultText
    }

    /// The saved override, or nil when the shipped default is in use. An
    /// empty override is treated as no override: a prompt-less call would
    /// make the model do something unrecognisable, and the Save button
    /// isn't the place to discover that.
    static func stored(for kind: PromptKind) -> String? {
        guard let saved = UserDefaults.standard.string(forKey: kind.defaultsKey),
              !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return saved
    }
}

/// UI-side wrapper over the same defaults, so the settings row and the
/// editor can show which prompts have been changed.
@MainActor
final class PromptStore: ObservableObject {
    /// Bumped on every save or reset; views observing it re-read through
    /// `PromptLibrary`, which keeps one source of truth for the values.
    @Published private(set) var revision = 0

    func text(for kind: PromptKind) -> String {
        PromptLibrary.text(for: kind)
    }

    func isCustomized(_ kind: PromptKind) -> Bool {
        guard let stored = PromptLibrary.stored(for: kind) else { return false }
        return stored != kind.defaultText
    }

    var customizedCount: Int {
        PromptKind.allCases.count(where: { isCustomized($0) })
    }

    /// Saving text identical to the default clears the override instead of
    /// storing a copy of it — otherwise a later change to the shipped
    /// prompt would be silently shadowed by the duplicate.
    func save(_ text: String, for kind: PromptKind) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == kind.defaultText.trimmingCharacters(in: .whitespacesAndNewlines) {
            UserDefaults.standard.removeObject(forKey: kind.defaultsKey)
        } else {
            UserDefaults.standard.set(text, forKey: kind.defaultsKey)
        }
        revision += 1
    }

    func reset(_ kind: PromptKind) {
        UserDefaults.standard.removeObject(forKey: kind.defaultsKey)
        revision += 1
    }
}
