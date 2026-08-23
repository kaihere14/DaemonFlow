//
//  VocabularyCorrector.swift
//  DaemonFlow
//
//  Fuzzy spelling repair against the user's custom dictionary. Speech
//  models reliably mangle names they were never trained on ("DaemonFlow"
//  comes back as "demon flow", "Whisper Flow" as "wisperflow"), and no
//  amount of cleanup prompting fixes that — the LLM has no idea what the
//  right spelling was either. So the user tells us the spellings they
//  care about, and anything close enough gets rewritten to match.
//

import Foundation

/// Rewrites near-misses of user-supplied terms to their exact spelling.
/// Nonisolated and stateless so the transcription pipeline can call it
/// from its background task with a plain `[String]` snapshot of the
/// dictionary.
nonisolated enum VocabularyCorrector {
    /// How far a candidate may stray from a dictionary term, by the
    /// length of the longer of the two.
    ///
    /// Short terms get **zero** edit budget on purpose: at four characters
    /// a single edit is the distance between two unrelated English words
    /// ("form"/"farm", "sync"/"sink"), so fuzzy matching there would
    /// corrupt ordinary dictation. Those entries still get their casing
    /// normalized, which is most of what a short custom term needs
    /// ("kubectl", "iOS").
    private static func editBudget(for length: Int) -> Int {
        switch length {
        case ...4: return 0
        case 5...7: return 1
        case 8...11: return 2
        default: return max(2, length / 5)
        }
    }

    /// Second gate, applied on top of the budget: even a permitted number
    /// of edits has to leave most of the word intact.
    private static let minimumSimilarity = 0.8

    /// Applies every term to `text`, leaving whitespace, punctuation and
    /// everything the dictionary doesn't cover untouched. Returns `text`
    /// unchanged when the dictionary is empty.
    static func apply(_ text: String, terms: [String]) -> String {
        let prepared = prepare(terms)
        guard !prepared.isEmpty, !text.isEmpty else { return text }

        let (separators, tokens, trailing) = tokenize(text)
        guard !tokens.isEmpty else { return text }

        var output = ""
        var index = 0

        while index < tokens.count {
            if let match = bestMatch(in: tokens, at: index, terms: prepared) {
                let first = splitAffixes(tokens[index])
                let last = splitAffixes(tokens[index + match.width - 1])
                output += separators[index] + first.prefix + match.term + last.suffix
                index += match.width
            } else {
                output += separators[index] + tokens[index]
                index += 1
            }
        }

        return output + trailing
    }

    // MARK: - Terms

    private struct PreparedTerm {
        let text: String
        let lowercased: String
        let wordCount: Int
    }

    /// Longest terms first, so "Whisper Flow" claims the window before the
    /// single-word "Flow" gets a look at it.
    private static func prepare(_ terms: [String]) -> [PreparedTerm] {
        terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map {
                PreparedTerm(
                    text: $0,
                    lowercased: $0.lowercased(),
                    wordCount: $0.split(whereSeparator: \.isWhitespace).count
                )
            }
            .sorted {
                $0.wordCount != $1.wordCount
                    ? $0.wordCount > $1.wordCount
                    : $0.text.count > $1.text.count
            }
    }

    // MARK: - Matching

    private struct Match {
        let term: String
        let width: Int
    }

    /// Tries every term against every plausible window starting at
    /// `index`. Windows run from one token up to one more than the term's
    /// own word count, because the model splits and merges in both
    /// directions: "DaemonFlow" arrives as two tokens, "Whisper Flow" as
    /// one.
    ///
    /// The widest *permitted* window is not the widest *correct* one —
    /// "whisper flow vs" is within budget of "Whisper Flow" purely because
    /// deleting " vs" is only three edits. So each term takes its
    /// lowest-distance window, tie-broken toward the term's own word
    /// count, which is what stops a match from eating the word after it.
    private static func bestMatch(in tokens: [String], at index: Int, terms: [PreparedTerm]) -> Match? {
        for term in terms {
            let widestWindow = min(term.wordCount + 1, tokens.count - index)
            guard widestWindow >= 1 else { continue }

            var best: (width: Int, distance: Int, widthError: Int)?

            for width in 1...widestWindow {
                guard let candidate = candidate(from: tokens, at: index, width: width) else { continue }
                guard let distance = matchDistance(candidate: candidate, term: term) else { continue }

                let widthError = abs(width - term.wordCount)
                if let current = best, (current.distance, current.widthError) <= (distance, widthError) {
                    continue
                }
                best = (width, distance, widthError)
            }

            if let best {
                return Match(term: term.text, width: best.width)
            }
        }
        return nil
    }

    /// The comparable text of a token window: each token stripped of its
    /// surrounding punctuation and rejoined with single spaces. Returns
    /// nil when punctuation *inside* the window rules it out — a comma
    /// between two words means they aren't one term, and collapsing them
    /// would silently eat the comma.
    private static func candidate(from tokens: [String], at index: Int, width: Int) -> String? {
        var cores: [String] = []
        cores.reserveCapacity(width)

        for offset in 0..<width {
            let parts = splitAffixes(tokens[index + offset])
            guard !parts.core.isEmpty else { return nil }
            if offset > 0, !parts.prefix.isEmpty { return nil }
            if offset < width - 1, !parts.suffix.isEmpty { return nil }
            cores.append(parts.core)
        }

        return cores.joined(separator: " ")
    }

    /// The edit distance between a window and a term, or nil when they're
    /// too far apart to be the same thing.
    private static func matchDistance(candidate: String, term: PreparedTerm) -> Int? {
        let lowered = candidate.lowercased()
        if lowered == term.lowercased { return 0 }

        let longest = max(lowered.count, term.lowercased.count)
        let budget = editBudget(for: longest)
        guard budget > 0 else { return nil }
        // Cheap reject before paying for the full matrix.
        guard abs(lowered.count - term.lowercased.count) <= budget else { return nil }

        let distance = editDistance(Array(lowered), Array(term.lowercased), limit: budget)
        guard distance <= budget else { return nil }
        guard 1 - Double(distance) / Double(longest) >= minimumSimilarity else { return nil }

        return distance
    }

    // MARK: - Text utilities

    /// Splits a token into leading punctuation, the word itself, and
    /// trailing punctuation, so `("Wisperflow,")` can be rewritten without
    /// losing the quote or the comma. Apostrophes and hyphens inside a
    /// word stay part of the core.
    private static func splitAffixes(_ token: String) -> (prefix: String, core: String, suffix: String) {
        let characters = Array(token)
        var start = 0
        var end = characters.count

        while start < end, !characters[start].isLetter, !characters[start].isNumber {
            start += 1
        }
        while end > start, !characters[end - 1].isLetter, !characters[end - 1].isNumber {
            end -= 1
        }

        return (
            prefix: String(characters[0..<start]),
            core: String(characters[start..<end]),
            suffix: String(characters[end...])
        )
    }

    /// Whitespace-preserving tokenizer. `separators[i]` is the whitespace
    /// that preceded `tokens[i]`, and `trailing` is whatever followed the
    /// last one — so reassembly reproduces the original newlines and
    /// double spaces exactly.
    private static func tokenize(_ text: String) -> (separators: [String], tokens: [String], trailing: String) {
        var separators: [String] = []
        var tokens: [String] = []
        var pendingSeparator = ""
        var current = ""

        for character in text {
            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                pendingSeparator.append(character)
            } else {
                if current.isEmpty {
                    separators.append(pendingSeparator)
                    pendingSeparator = ""
                }
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return (separators, tokens, pendingSeparator)
    }

    /// Levenshtein distance, abandoned early once every alignment in the
    /// row already exceeds `limit` — dictionary terms are short, but this
    /// runs on every token of every transcript.
    private static func editDistance(_ lhs: [Character], _ rhs: [Character], limit: Int) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            var rowMinimum = i

            for j in 1...rhs.count {
                let substitution = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + substitution
                )
                rowMinimum = min(rowMinimum, current[j])
            }

            if rowMinimum > limit { return limit + 1 }
            swap(&previous, &current)
        }

        return previous[rhs.count]
    }
}
