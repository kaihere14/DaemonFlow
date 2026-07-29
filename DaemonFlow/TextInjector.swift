//
//  TextInjector.swift
//  DaemonFlow
//

import AppKit
import ApplicationServices
import os

/// Pastes text into whatever app currently has keyboard focus, by
/// temporarily taking over the general pasteboard and synthesizing Cmd+V.
/// Requires Accessibility permission (already needed for the Fn hotkey).
@MainActor
final class TextInjector {
    private static let pasteboardRestoreDelay: TimeInterval = 0.4

    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "injection")

    func inject(_ text: String) {
        guard !text.isEmpty else { return }

        if !AXIsProcessTrusted() {
            logger.error("Injecting without Accessibility trust — synthesized Cmd+V will be dropped by the system")
        }
        logger.info("Injecting \(text.count, privacy: .public) chars into frontmost app")

        let pasteboard = NSPasteboard.general

        // Snapshot every item's full contents (all types, not just strings)
        // so we can put the user's clipboard back exactly as it was.
        let savedItems: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCmdV()

        // Restore only after the target app has had time to service the
        // paste — restoring too early would paste the old clipboard instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteboardRestoreDelay) {
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
    }

    private func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
