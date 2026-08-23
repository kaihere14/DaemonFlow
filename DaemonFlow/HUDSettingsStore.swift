//
//  HUDSettingsStore.swift
//  DaemonFlow
//

import AppKit
import Combine
import Foundation
import SwiftUI
import os

/// A user-picked colour stored as sRGB components. SwiftUI's `Color` isn't
/// Codable, and archiving an `NSColor` would put an opaque blob in
/// UserDefaults that can't be read back by anything else.
struct HUDColor: Equatable, Codable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255,
            opacity: opacity
        )
    }

    /// Round-trips whatever the ColorPicker hands back into sRGB. A colour
    /// picked from the wheel can be in any space, and reading components
    /// off it without converting first throws.
    init(_ color: Color) {
        let converted = NSColor(color).usingColorSpace(.sRGB)
        guard let converted else {
            self.init(red: 1, green: 1, blue: 1)
            return
        }
        self.init(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent),
            opacity: Double(converted.alphaComponent)
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// Dimensions of the floating pill, in points. Only the two base sizes are
/// stored — the transcript pill is derived from the active one, so the
/// three states can't drift out of proportion with each other.
struct HUDAppearance: Equatable, Codable, Sendable {
    /// The always-visible sliver, when "always show the pill" is on.
    var restingWidth: Double = 64
    var restingHeight: Double = 8

    /// The pill while recording, transcribing or refining — the waveform
    /// scales to fill it.
    var activeWidth: Double = 88
    var activeHeight: Double = 22

    /// Fill behind the pill in every state. Slightly transparent by
    /// default so the desktop shows through the way the rest of the app's
    /// surfaces do.
    var backgroundColor = HUDColor(hex: "15181D", opacity: 0.97)

    /// Ink for the live indicators: the waveform bars, the transcribing
    /// spinner and the ⌥1 wand. One colour rather than three — they're the
    /// same signal in different states, and picking them apart made the
    /// pill read as three unrelated widgets.
    var waveformColor = HUDColor(hex: "7C5CFF")

    /// Outline while the pill is doing something — recording, transcribing,
    /// refining.
    var borderColor = HUDColor(hex: "242832")

    /// Outline of the resting sliver. Separate from `borderColor` so the
    /// pill can say at a glance whether it's listening or asleep.
    var restingBorderColor = HUDColor(hex: "242832")

    /// Applies to both borders. 0 hides them entirely.
    var borderWidth: Double = 1

    static let restingWidthRange: ClosedRange<Double> = 32...180
    static let restingHeightRange: ClosedRange<Double> = 4...24
    static let activeWidthRange: ClosedRange<Double> = 64...200
    static let activeHeightRange: ClosedRange<Double> = 16...44
    static let borderWidthRange: ClosedRange<Double> = 0...4

    /// Space between the waveform and the live transcript, and the pill's
    /// inner horizontal inset. Not user-facing — they're what makes the
    /// derived sizes below add up.
    static let contentSpacing: Double = 8
    static let horizontalPadding: Double = 12

    /// Fixed so the transcript wraps at the same point regardless of how
    /// wide the waveform is — a text column that resized with the meter
    /// would rewrap mid-sentence every time the settings changed.
    static let liveTextWidth: Double = 168

    var expandedWidth: Double { activeWidth + Self.contentSpacing + Self.liveTextWidth }

    /// Tall enough for two lines of transcript no matter how short the
    /// active pill is.
    var expandedHeight: Double { max(activeHeight + 12, 34) }

    /// The largest the pill can ever get, which is what the panel behind
    /// it has to be sized for.
    static var maximumSize: CGSize {
        var largest = HUDAppearance()
        largest.activeWidth = activeWidthRange.upperBound
        largest.activeHeight = activeHeightRange.upperBound
        return CGSize(
            width: max(largest.expandedWidth, restingWidthRange.upperBound),
            height: max(largest.expandedHeight, restingHeightRange.upperBound)
        )
    }

    /// Mutates a copy rather than rebuilding the struct, so a field added
    /// later doesn't silently get reset to its default on the way in.
    func clamped() -> HUDAppearance {
        var clamped = self
        clamped.restingWidth = restingWidth.clamped(to: Self.restingWidthRange)
        clamped.restingHeight = restingHeight.clamped(to: Self.restingHeightRange)
        clamped.activeWidth = activeWidth.clamped(to: Self.activeWidthRange)
        clamped.activeHeight = activeHeight.clamped(to: Self.activeHeightRange)
        clamped.borderWidth = borderWidth.clamped(to: Self.borderWidthRange)
        return clamped
    }
}

extension HUDAppearance {
    /// Hand-rolled so settings saved before the colour options existed
    /// still decode — the synthesised initialiser treats every missing key
    /// as an error and would throw the user's sizes away.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HUDAppearance()
        self.init()
        restingWidth = try container.decodeIfPresent(Double.self, forKey: .restingWidth) ?? defaults.restingWidth
        restingHeight = try container.decodeIfPresent(Double.self, forKey: .restingHeight) ?? defaults.restingHeight
        activeWidth = try container.decodeIfPresent(Double.self, forKey: .activeWidth) ?? defaults.activeWidth
        activeHeight = try container.decodeIfPresent(Double.self, forKey: .activeHeight) ?? defaults.activeHeight
        backgroundColor = try container.decodeIfPresent(HUDColor.self, forKey: .backgroundColor) ?? defaults.backgroundColor
        waveformColor = try container.decodeIfPresent(HUDColor.self, forKey: .waveformColor) ?? defaults.waveformColor
        borderColor = try container.decodeIfPresent(HUDColor.self, forKey: .borderColor) ?? defaults.borderColor
        restingBorderColor = try container.decodeIfPresent(HUDColor.self, forKey: .restingBorderColor) ?? defaults.restingBorderColor
        borderWidth = try container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? defaults.borderWidth
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Everything the user can change about the floating pill. Small enough to
/// live in UserDefaults rather than earning its own file in Application
/// Support like the transcript history and vocabulary do.
@MainActor
final class HUDSettingsStore: ObservableObject {
    private static let alwaysVisibleKey = "hudAlwaysVisible"
    private static let appearanceKey = "hudAppearance"

    /// Keeps the pill on screen as a thin resting sliver instead of hiding
    /// it between dictations. Off by default — a permanent floating
    /// element above the Dock is a preference, not something to impose.
    @Published var alwaysVisible: Bool {
        didSet { UserDefaults.standard.set(alwaysVisible, forKey: Self.alwaysVisibleKey) }
    }

    @Published var appearance: HUDAppearance {
        didSet { persistAppearance() }
    }

    private let logger = Logger(subsystem: daemonFlowLogSubsystem, category: "hud")

    init() {
        // Falls back to the key this setting shipped under before the HUD
        // preferences were split out of AppState.
        alwaysVisible = UserDefaults.standard.object(forKey: Self.alwaysVisibleKey) as? Bool
            ?? UserDefaults.standard.bool(forKey: "alwaysShowHUD")

        if let data = UserDefaults.standard.data(forKey: Self.appearanceKey),
           let decoded = try? JSONDecoder().decode(HUDAppearance.self, from: data) {
            // Clamped on the way in: a value saved before a range changed
            // would otherwise render a pill that doesn't fit its panel.
            appearance = decoded.clamped()
        } else {
            appearance = HUDAppearance()
        }
    }

    /// Sizes and colours reset independently — someone who has spent time
    /// on a palette shouldn't lose it by putting the sliders back.
    func resetSizes() {
        let defaults = HUDAppearance()
        appearance.restingWidth = defaults.restingWidth
        appearance.restingHeight = defaults.restingHeight
        appearance.activeWidth = defaults.activeWidth
        appearance.activeHeight = defaults.activeHeight
    }

    func resetColors() {
        let defaults = HUDAppearance()
        appearance.backgroundColor = defaults.backgroundColor
        appearance.waveformColor = defaults.waveformColor
        appearance.borderColor = defaults.borderColor
        appearance.restingBorderColor = defaults.restingBorderColor
        appearance.borderWidth = defaults.borderWidth
    }

    var areSizesDefault: Bool {
        let defaults = HUDAppearance()
        return appearance.restingWidth == defaults.restingWidth
            && appearance.restingHeight == defaults.restingHeight
            && appearance.activeWidth == defaults.activeWidth
            && appearance.activeHeight == defaults.activeHeight
    }

    var areColorsDefault: Bool {
        let defaults = HUDAppearance()
        return appearance.backgroundColor == defaults.backgroundColor
            && appearance.waveformColor == defaults.waveformColor
            && appearance.borderColor == defaults.borderColor
            && appearance.restingBorderColor == defaults.restingBorderColor
            && appearance.borderWidth == defaults.borderWidth
    }

    private func persistAppearance() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(appearance), forKey: Self.appearanceKey)
        } catch {
            logger.error("Couldn't save HUD appearance: \(error.localizedDescription, privacy: .public)")
        }
    }
}
