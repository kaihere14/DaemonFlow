//
//  HotkeyManager.swift
//  DaemonFlow
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import os

nonisolated let daemonFlowLogSubsystem = "armandev.space.DaemonFlow"

@MainActor
final class HotkeyManager: ObservableObject {
    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "hotkey")
    @Published var isRecording: Bool = false
    @Published var isHandsFreeMode: Bool = false
    /// Fires when the user presses ⌥1 — AppState reacts by refining the
    /// currently selected text in the frontmost app.
    let refineTriggered = PassthroughSubject<Void, Never>()
    @Published var needsAccessibilityPermission: Bool = false
    /// Input Monitoring — a distinct TCC service from Accessibility. A
    /// `.cghidEventTap` (HID-level, which is what global Fn detection
    /// requires) needs THIS permission to receive events system-wide;
    /// Accessibility alone governs posting synthesized events (our paste).
    @Published var needsInputMonitoringPermission: Bool = false

    private static let doubleTapWindow: CFAbsoluteTime = 0.3

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustMonitorTimer: Timer?

    private var fnIsDown = false
    private var lastReleaseTime: CFAbsoluteTime?

    init() {
        needsAccessibilityPermission = !AXIsProcessTrusted()
        needsInputMonitoringPermission = !CGPreflightListenEventAccess()
        setupEventTap()
        startTrustMonitor()
    }

    deinit {
        trustMonitorTimer?.invalidate()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    /// Call after the user grants Accessibility and/or Input Monitoring
    /// permission and returns to the app. Always rebuilds the tap: a tap
    /// created while untrusted only receives our own app's events, and
    /// stays degraded even after trust is granted — recreating it is the
    /// only way to get global delivery.
    func retryEventTap() {
        rebuildEventTap()
    }

    /// Trust can change behind our back — the user toggles System Settings,
    /// or a rebuild invalidates the TCC grant. Poll so the UI stays truthful
    /// and the tap is rebuilt automatically when trust appears.
    private func startTrustMonitor() {
        trustMonitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTrustState()
            }
        }
    }

    private func refreshTrustState() {
        let trusted = AXIsProcessTrusted()
        let listenGranted = CGPreflightListenEventAccess()
        var shouldRebuild = false

        if trusted && needsAccessibilityPermission {
            logger.info("Accessibility trust granted")
            shouldRebuild = true
        } else if !trusted && !needsAccessibilityPermission {
            logger.warning("Accessibility trust lost (revoked, or the app was re-signed by a rebuild)")
            needsAccessibilityPermission = true
        }

        if listenGranted && needsInputMonitoringPermission {
            logger.info("Input Monitoring granted")
            shouldRebuild = true
        } else if !listenGranted && !needsInputMonitoringPermission {
            logger.warning("Input Monitoring lost (revoked, or the app was re-signed by a rebuild)")
            needsInputMonitoringPermission = true
        }

        if shouldRebuild {
            logger.info("Rebuilding event tap for global delivery")
            rebuildEventTap()
        }
    }

    private func rebuildEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        setupEventTap()
    }

    func openAccessibilitySettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Triggers the native system prompt for Input Monitoring. Only has an
    /// effect the first time the process identity is asked — after a
    /// denial (or on repeat rebuilds of an ad-hoc-signed app), macOS
    /// silently no-ops this and the user must use System Settings instead.
    func requestInputMonitoringAccess() {
        _ = CGRequestListenEventAccess()
    }

    private func setupEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // .defaultTap (active), not .listenOnly: the ⌥1 refine hotkey must
        // be swallowed (callback returns nil) or the frontmost app would
        // receive it and type "¡" into the very text being refined. Fn
        // flagsChanged events are still passed through untouched.
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventTapCallback,
            userInfo: refcon
        ) else {
            // Either Accessibility or Input Monitoring permission isn't
            // granted yet, or tap creation failed for another reason.
            // Don't crash — surface it to the UI and let retryEventTap()
            // try again later.
            logger.error("Event tap creation failed — likely missing Accessibility or Input Monitoring permission")
            needsAccessibilityPermission = !AXIsProcessTrusted()
            needsInputMonitoringPermission = !CGPreflightListenEventAccess()
            eventTap = nil
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            logger.error("CFMachPortCreateRunLoopSource failed")
            needsAccessibilityPermission = !AXIsProcessTrusted()
            needsInputMonitoringPermission = !CGPreflightListenEventAccess()
            eventTap = nil
            return
        }

        eventTap = tap
        runLoopSource = source
        // Tap creation succeeding does NOT prove trust: an untrusted tap is
        // silently degraded to own-app events only. Report actual TCC state.
        needsAccessibilityPermission = !AXIsProcessTrusted()
        needsInputMonitoringPermission = !CGPreflightListenEventAccess()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Event tap created and enabled (accessibility: \(AXIsProcessTrusted(), privacy: .public), inputMonitoring: \(CGPreflightListenEventAccess(), privacy: .public))")
    }

    /// Bridge from the non-isolated C callback into actor-isolated state.
    fileprivate nonisolated func handleTapCallback(disabled: Bool, fnDown: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if disabled {
                self.reenableTapIfNeeded()
                return
            }
            self.processFnFlagChange(isDown: fnDown)
        }
    }

    /// Bridge for the ⌥1 refine hotkey, same pattern as above.
    fileprivate nonisolated func handleRefineHotkey() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Refine hotkey (⌥1) pressed")
            self.refineTriggered.send()
        }
    }

    private func reenableTapIfNeeded() {
        guard let eventTap else { return }
        logger.warning("Event tap was disabled by the system — re-enabling")
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func processFnFlagChange(isDown: Bool) {
        guard isDown != fnIsDown else { return }
        fnIsDown = isDown
        logger.debug("Fn \(isDown ? "pressed" : "released", privacy: .public)")

        if isDown {
            handleFnPress()
        } else {
            handleFnRelease()
        }
    }

    private func handleFnPress() {
        // In hands-free mode, isRecording is driven by the toggle, not by hold/release.
        guard !isHandsFreeMode else { return }
        isRecording = true
    }

    private func handleFnRelease() {
        let now = CFAbsoluteTimeGetCurrent()

        if isHandsFreeMode {
            // Any single tap while hands-free is active turns it off.
            isHandsFreeMode = false
            isRecording = false
            lastReleaseTime = nil
            return
        }

        isRecording = false

        if let lastReleaseTime, now - lastReleaseTime < Self.doubleTapWindow {
            self.lastReleaseTime = nil
            isHandsFreeMode = true
            isRecording = true
        } else {
            lastReleaseTime = now
        }
    }
}

/// C-ABI callback for CGEventTap. Must be a non-capturing, non-isolated
/// global function — the tap invokes this synchronously off the Swift
/// concurrency model, so all it does is extract the Fn flag and hand off
/// to the manager, which hops back to the main actor itself.
private nonisolated func hotkeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        manager.handleTapCallback(disabled: true, fnDown: false)
        return Unmanaged.passUnretained(event)
    }

    if type == .keyDown {
        // ⌥1 (keycode 18) with no other command/control/shift modifiers:
        // the refine-selection hotkey. Swallow it (return nil) so the "¡"
        // character never reaches the frontmost app.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if keyCode == 18,
           flags.contains(.maskAlternate),
           !flags.contains(.maskCommand),
           !flags.contains(.maskControl),
           !flags.contains(.maskShift) {
            manager.handleRefineHotkey()
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged else {
        return Unmanaged.passUnretained(event)
    }

    let fnDown = event.flags.contains(.maskSecondaryFn)
    manager.handleTapCallback(disabled: false, fnDown: fnDown)

    return Unmanaged.passUnretained(event)
}
