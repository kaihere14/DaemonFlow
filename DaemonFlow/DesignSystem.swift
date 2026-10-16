//
//  DesignSystem.swift
//  DaemonFlow
//
//  The app leans on native macOS controls, materials and semantic colours,
//  so this file is deliberately small: the motion values every custom
//  animation shares, and the handful of components AppKit/SwiftUI don't
//  ship. Values follow the project's UI skills (.claude/skills): ease-out
//  for anything entering, exits shorter than entrances, nothing user-driven
//  over 300ms, and movement/scale/blur dropped under Reduce Motion.
//

import AppKit
import SwiftUI

// MARK: - Motion

enum Motion {
    /// Press feedback on custom controls.
    static let press = Animation.easeOut(duration: 0.15)

    /// Entrances: strong ease-out, so movement starts the instant the
    /// element appears and settles gently.
    static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)

    /// Exits run shorter than entrances — the system is responding, not
    /// presenting.
    static let exit = Animation.easeOut(duration: 0.15)

    /// Something already on screen changing shape or position.
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)

    /// Contextual icon swaps (copy → copied, download → in use). No bounce.
    static let iconSwap = Animation.spring(duration: 0.3, bounce: 0)

    /// Delay between semantic chunks of a staged entrance.
    static let staggerStep: Double = 0.1
}

// MARK: - Transitions

/// Contextual icon cross-fade: scale 0.25 → 1, opacity 0 → 1, blur 4 → 0.
/// Under Reduce Motion only the fade remains.
struct IconSwapTransition: Transition {
    var reduceMotion = false

    func body(content: Content, phase: TransitionPhase) -> some View {
        let hidden = !phase.isIdentity
        content
            .opacity(hidden ? 0 : 1)
            .scaleEffect(hidden && !reduceMotion ? 0.25 : 1)
            .blur(radius: hidden && !reduceMotion ? 4 : 0)
    }
}

/// For swapping whole controls (a button turning into a progress bar):
/// the same cross-fade as an icon swap, but a control shrinking to a
/// quarter of its size would read as it being thrown away.
struct ControlSwapTransition: Transition {
    var reduceMotion = false

    func body(content: Content, phase: TransitionPhase) -> some View {
        let hidden = !phase.isIdentity
        content
            .opacity(hidden ? 0 : 1)
            .scaleEffect(hidden && !reduceMotion ? 0.96 : 1)
            .blur(radius: hidden && !reduceMotion ? 4 : 0)
    }
}

// MARK: - Staged entrance

private struct StaggeredEntrance: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .blur(radius: isVisible || reduceMotion ? 0 : 4)
            .offset(y: isVisible || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(Motion.enter.delay(Double(index) * Motion.staggerStep)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    /// Fades, un-blurs and lifts the view into place on first appearance,
    /// `index` steps after its siblings. Reserved for rare moments — the
    /// onboarding screens — never routine navigation.
    func staggeredEntrance(_ index: Int) -> some View {
        modifier(StaggeredEntrance(index: index))
    }
}

// MARK: - Buttons

/// Scales a custom control to 0.96 while pressed. Native bordered buttons
/// keep the system's own press highlight; this is only for the bare
/// icon buttons that would otherwise give no feedback at all.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .opacity(pressed && reduceMotion ? 0.6 : 1)
            .animation(Motion.press, value: pressed)
    }
}

/// Borderless 24pt icon button: secondary at rest, primary under the
/// pointer. The colour change is instant — hovering is far too frequent
/// to be worth animating.
struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(isHovering ? .primary : .secondary)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Copies `text` and confirms with a checkmark for a moment. The swap is
/// infrequent and carries meaning, so it gets the icon cross-fade.
struct CopyButton: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button(action: copy) {
            ZStack {
                if copied {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .transition(IconSwapTransition(reduceMotion: reduceMotion))
                } else {
                    Image(systemName: "doc.on.doc")
                        .transition(IconSwapTransition(reduceMotion: reduceMotion))
                }
            }
            .font(.system(size: 12, weight: .regular))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .foregroundStyle(.secondary)
        .animation(Motion.iconSwap, value: copied)
        .help(copied ? "Copied" : "Copy")
        .accessibilityLabel(copied ? "Copied" : "Copy")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}

// MARK: - Small pieces

/// A key as it's drawn in macOS menus and help: a quiet rounded plate.
struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 18)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// White glyph on a tinted rounded square, the way System Settings marks
/// its rows.
struct SettingsGlyph: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Small tinted capsule marking the model to pick when unsure.
struct RecommendedTag: View {
    var body: some View {
        Text("Recommended")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.12), in: Capsule())
    }
}
