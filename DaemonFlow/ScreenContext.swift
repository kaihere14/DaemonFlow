//
//  ScreenContext.swift
//  DaemonFlow
//
//  Screen awareness for dictation. Speech models mangle names they were
//  never trained on ("Supabase" comes back as "super base"), but the word
//  the user is saying is very often right there on screen — in the doc
//  they're editing, the chat they're replying to, the page they're
//  reading. So when Fn goes down we read the text of the frontmost window
//  through the Accessibility API (the permission paste injection already
//  needs), pull out the handful of unusual terms in it, and hand those to
//  the speech and cleanup models as spelling hints. Nothing leaves the
//  machine.
//

import AppKit
import ApplicationServices
import os

/// Entry point for the pipeline: one call per dictation, started the
/// moment Fn is pressed so it runs while the user is still talking.
enum ScreenContext {
    private static let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "screen-context")

    /// Distinctive terms visible in the frontmost window, most relevant
    /// first, minus anything already in `known` (the custom dictionary
    /// reaches the models on its own). Empty when there's nothing usable
    /// or DaemonFlow itself is frontmost.
    static func captureTerms(excluding known: [String]) async -> [String] {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return [] }

        let pid = app.processIdentifier
        let started = ContinuousClock.now
        // AX calls are synchronous IPC into the target app — kept off the
        // main actor so a slow app can't stall the HUD.
        let text = await Task.detached(priority: .userInitiated) {
            ScreenTextReader.readFocusedWindow(of: pid)
        }.value
        let terms = ScreenTermExtractor.terms(in: text, excluding: known)

        let elapsed = ContinuousClock.now - started
        logger.info("Read \(text.count, privacy: .public) chars from \(app.bundleIdentifier ?? "unknown", privacy: .public) in \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public) — \(terms.count, privacy: .public) terms: \(terms.joined(separator: ", "), privacy: .public)")
        return terms
    }
}

/// Breadth-first walk of the focused window's accessibility tree,
/// collecting every piece of text it exposes. Bounded three ways — per
/// message, overall time, and element count — because some apps expose
/// enormous trees and some answer slowly or not at all.
nonisolated enum ScreenTextReader {
    /// Per-call ceiling for a single AX round trip to the target app.
    private static let messagingTimeout: Float = 0.2
    /// The whole walk gives up after this, keeping whatever it has.
    private static let deadline: Duration = .milliseconds(500)
    private static let maxElements = 3000
    private static let characterBudget = 30_000
    /// A text area holding more than this (a source file, a long chat) is
    /// trimmed to the part actually scrolled into view.
    private static let longValueThreshold = 2000

    /// Fetched in one round trip per element instead of one per
    /// attribute — the difference between ~50ms and over a second on a
    /// busy web page.
    private static let attributes = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXValueAttribute,
        kAXTitleAttribute,
        kAXDescriptionAttribute,
        kAXChildrenAttribute,
    ] as CFArray

    static func readFocusedWindow(of pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        // Chromium and Electron only build their accessibility tree once
        // an assistive client asks for it. (AXEnhancedUserInterface would
        // do it too, but it's known to break window animations.)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let window = element(app, kAXFocusedWindowAttribute) ?? elements(app, kAXWindowsAttribute)?.first else {
            return ""
        }

        let clock = ContinuousClock()
        let stopAt = clock.now + deadline

        var queue = [window]
        var head = 0
        var seen = Set<String>()
        var pieces: [String] = []
        var remaining = characterBudget

        while head < queue.count, head < maxElements, remaining > 0, clock.now < stopAt {
            let current = queue[head]
            head += 1

            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(current, attributes, AXCopyMultipleAttributeOptions(), &raw) == .success,
                  let values = raw as? [Any], values.count == 6
            else { continue }

            // Never read password fields — not even to discard the text.
            if values[1] as? String == kAXSecureTextFieldSubrole { continue }

            var texts: [String] = []
            if let value = values[2] as? String {
                if value.count > longValueThreshold {
                    texts.append(visibleSubstring(of: current) ?? String(value.prefix(longValueThreshold)))
                } else {
                    texts.append(value)
                }
            }
            if let title = values[3] as? String { texts.append(title) }
            if let description = values[4] as? String { texts.append(description) }

            for text in texts {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
                pieces.append(trimmed)
                remaining -= trimmed.count
            }

            if let children = values[5] as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }

        return pieces.joined(separator: "\n")
    }

    private static func visibleSubstring(of element: AXUIElement) -> String? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &range) == .success,
              let range
        else { return nil }

        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            range,
            &text
        ) == .success else { return nil }
        return text as? String
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ parent: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }
}

/// Distills a window's worth of text down to the words a speech model is
/// likely to get wrong: product names, identifiers, jargon. Ordinary
/// English is dropped — the models already spell it fine, and every extra
/// term is a chance for the cleanup model to "correct" something that
/// wasn't wrong.
enum ScreenTermExtractor {
    /// Enough to cover a busy screen, small enough to stay well inside
    /// Whisper's prompt window and not drown a 1B cleanup model.
    static let maxTerms = 40

    /// Spell-checking is the expensive step, so only the most frequent
    /// candidates get that far.
    private static let maxSpellChecks = 800

    private struct Candidate {
        var count = 0
        var spellings: [String: Int] = [:]

        /// The casing seen most often, preferring one with capitals on a
        /// tie — "Supabase" over the "supabase" in its URL.
        var preferredSpelling: String {
            spellings.max { lhs, rhs in
                lhs.value != rhs.value
                    ? lhs.value < rhs.value
                    : !lhs.key.contains(where: \.isUppercase) && rhs.key.contains(where: \.isUppercase)
            }?.key ?? ""
        }
    }

    static func terms(in text: String, excluding known: [String]) -> [String] {
        guard !text.isEmpty else { return [] }
        let knownKeys = Set(known.map { $0.lowercased() })

        var candidates: [String: Candidate] = [:]
        for token in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(token)
            guard isPlausibleTerm(word) else { continue }
            let key = word.lowercased()
            guard !knownKeys.contains(key) else { continue }
            candidates[key, default: Candidate()].count += 1
            candidates[key, default: Candidate()].spellings[word, default: 0] += 1
        }

        let ranked = candidates.values
            .map { candidate in
                let spelling = candidate.preferredSpelling
                return (spelling: spelling, score: candidate.count + (isObviouslyCoined(spelling) ? 3 : 0))
            }
            .sorted { $0.score > $1.score }
            .prefix(maxSpellChecks)

        let spellChecker = NSSpellChecker.shared
        var result: [String] = []
        for (spelling, _) in ranked {
            if isObviouslyCoined(spelling) || !isDictionaryWord(spelling.lowercased(), spellChecker) {
                result.append(spelling)
                if result.count == maxTerms { break }
            }
        }
        return result
    }

    /// Rules out what can't usefully be dictated: short words (no room
    /// for a mishearing to be fixable), long strings (hashes, tokens),
    /// and anything mostly digits (version numbers, commit SHAs).
    private static func isPlausibleTerm(_ word: String) -> Bool {
        guard (4...30).contains(word.count) else { return false }
        let letters = word.reduce(0) { $0 + ($1.isLetter ? 1 : 0) }
        return letters >= 3 && letters * 2 >= word.count
    }

    /// Internal capitals ("DaemonFlow", "iOS") or embedded digits
    /// ("GPT4o") mark a coined name without needing a dictionary lookup.
    private static func isObviouslyCoined(_ word: String) -> Bool {
        let hasInternalUppercase = word.dropFirst().contains(where: \.isUppercase) && word.contains(where: \.isLowercase)
        return hasInternalUppercase || word.contains(where: \.isNumber)
    }

    private static func isDictionaryWord(_ word: String, _ spellChecker: NSSpellChecker) -> Bool {
        spellChecker.checkSpelling(of: word, startingAt: 0).location == NSNotFound
    }
}
