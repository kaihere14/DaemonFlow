//
//  SelectionRefiner.swift
//  DaemonFlow
//
//  Captures the currently selected text in the frontmost app by
//  synthesizing Cmd+C and reading the pasteboard, restoring the user's
//  clipboard immediately afterwards. Used by the ⌥1 refine action;
//  requires Accessibility permission (already needed for paste injection).
//

import AppKit
import os

@MainActor
final class SelectionRefiner {
    /// How long to wait for the frontmost app to service the synthesized
    /// Cmd+C before concluding nothing was selected.
    private static let copyTimeout: TimeInterval = 1.0
    private static let pollInterval: Duration = .milliseconds(50)

    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "refine")

    /// Returns the selected text in the frontmost app, or nil when nothing
    /// is selected (the pasteboard never changes after Cmd+C). The user's
    /// clipboard is snapshotted before the copy and restored before
    /// returning, so this never clobbers what they had copied.
    func captureSelectedText() async -> String? {
        let pasteboard = NSPasteboard.general

        let savedItems: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
        let startCount = pasteboard.changeCount

        postCmdC()

        var copied: String?
        let deadline = Date().addingTimeInterval(Self.copyTimeout)
        while Date() < deadline {
            try? await Task.sleep(for: Self.pollInterval)
            if pasteboard.changeCount != startCount {
                copied = pasteboard.string(forType: .string)
                break
            }
        }

        restore(savedItems, to: pasteboard)

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.info("Refine triggered with no text selected — ignoring")
            return nil
        }
        logger.info("Captured \(copied.count, privacy: .public) selected chars for refine")
        return copied
    }

    private func restore(_ savedItems: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = savedItems.compactMap { contents -> NSPasteboardItem? in
            guard !contents.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func postCmdC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKeyCode: CGKeyCode = 8

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
