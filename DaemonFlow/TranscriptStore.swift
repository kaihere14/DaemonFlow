//
//  TranscriptStore.swift
//  DaemonFlow
//

import Foundation
import os

/// One dictation: what Whisper heard (`rawText`) and what actually got
/// pasted (`text` — the cleaned version, or the raw text again when
/// cleanup was skipped or failed).
///
/// `date` is the moment the recording *ended*, not the moment
/// transcription finished. Those differ by however long the model took,
/// and two utterances dictated back-to-back can finish out of order —
/// stamping at recording end is what keeps the history in the order the
/// user actually spoke.
struct TranscriptEntry: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let date: Date
    let text: String
    let rawText: String

    init(id: UUID = UUID(), date: Date, text: String, rawText: String) {
        self.id = id
        self.date = date
        self.text = text
        self.rawText = rawText
    }

    /// True when cleanup actually changed something — the only case where
    /// showing the raw transcript alongside the cleaned one tells the user
    /// anything.
    var hasDistinctRawText: Bool {
        !rawText.isEmpty && rawText != text
    }
}

/// JSON-file-backed history. Transcripts survive relaunches instead of
/// living only in memory; the file is small (text only) and capped, so a
/// synchronous write per dictation is cheap and keeps the on-disk copy
/// correct even if the app is force-quit.
@MainActor
final class TranscriptStore {
    /// Oldest entries beyond this are dropped. ~200 dictations is months
    /// of history at a realistic usage rate and keeps the file well under
    /// a megabyte.
    static let maxEntries = 200

    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "history")

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("DaemonFlow", isDirectory: true)
            .appendingPathComponent("transcripts.json")
    }

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Returns the persisted history, newest first. A missing or corrupt
    /// file yields an empty history rather than an error — losing history
    /// is not worth blocking dictation over.
    func load() -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let entries = try decoder.decode([TranscriptEntry].self, from: data)
            return entries.sorted { $0.date > $1.date }
        } catch {
            logger.error("Couldn't decode transcript history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ entries: [TranscriptEntry]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(Array(entries.prefix(Self.maxEntries)))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Couldn't save transcript history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
