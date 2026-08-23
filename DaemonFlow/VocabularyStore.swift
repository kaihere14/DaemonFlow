//
//  VocabularyStore.swift
//  DaemonFlow
//

import Combine
import Foundation
import os

/// One entry in the custom dictionary: the exact spelling the user wants
/// to see. Stored with a stable id so the list can be edited in place
/// without SwiftUI losing track of rows mid-edit.
struct VocabularyTerm: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// JSON-file-backed custom dictionary, alongside the transcript history in
/// Application Support. Small enough that a synchronous write per edit is
/// cheaper than tracking dirty state.
@MainActor
final class VocabularyStore: ObservableObject {
    /// A guard against pathological input, not a product limit — the
    /// corrector is O(terms × tokens) and the list is hand-typed.
    static let maxTerms = 200

    @Published private(set) var terms: [VocabularyTerm] = []

    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "vocabulary")

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("DaemonFlow", isDirectory: true)
            .appendingPathComponent("vocabulary.json")
    }

    init() {
        terms = load()
    }

    /// Plain-string snapshot for the transcription pipeline, which runs off
    /// the main actor and shouldn't be reaching back into an
    /// ObservableObject to read it.
    var termStrings: [String] {
        terms.map(\.text)
    }

    /// Adds a term, ignoring blanks and case-insensitive duplicates.
    /// Returns false when nothing was added so the UI can keep the field's
    /// contents rather than silently swallowing them.
    @discardableResult
    func add(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, terms.count < Self.maxTerms else { return false }
        guard !terms.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }

        terms.append(VocabularyTerm(text: trimmed))
        save()
        return true
    }

    /// Commits an in-place edit. An emptied field deletes the row — that's
    /// the obvious reading of clearing it, and the alternative is a term
    /// that matches nothing.
    func update(_ id: VocabularyTerm.ID, to raw: String) {
        guard let index = terms.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            terms.remove(at: index)
        } else {
            guard terms[index].text != trimmed else { return }
            let isDuplicate = terms.contains {
                $0.id != id && $0.text.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            if isDuplicate {
                terms.remove(at: index)
            } else {
                terms[index].text = trimmed
            }
        }

        save()
    }

    func remove(_ id: VocabularyTerm.ID) {
        terms.removeAll { $0.id == id }
        save()
    }

    /// A missing or corrupt file yields an empty dictionary rather than an
    /// error — same trade as the transcript history, since blocking
    /// dictation over it would be worse than losing the list.
    private func load() -> [VocabularyTerm] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([VocabularyTerm].self, from: data)
        } catch {
            logger.error("Couldn't decode vocabulary: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(terms)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Couldn't save vocabulary: \(error.localizedDescription, privacy: .public)")
        }
    }
}
