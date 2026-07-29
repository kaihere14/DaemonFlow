//
//  Theme.swift
//  DaemonFlow
//

import SwiftUI

extension Color {
    init(hex: String) {
        let hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        var rgbValue: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255
        let b = Double(rgbValue & 0x0000FF) / 255

        self.init(red: r, green: g, blue: b)
    }
}

/// Shared visual language for DaemonFlow: a precise, technical instrument
/// rather than a marketing-style surface. `accent` is reserved for
/// selection/progress/recommendation signals only — never decorative.
enum Theme {
    static let background = Color(hex: "0B0D10")
    static let cardSurface = Color(hex: "15181D")
    static let cardSurfaceElevated = Color(hex: "1C2028")
    static let cardBorder = Color(hex: "242832")
    static let textPrimary = Color(hex: "EDEEF0")
    static let textSecondary = Color(hex: "8B909A")
    static let accent = Color(hex: "7C5CFF")
    static let successGreen = Color(hex: "4ADE80")

    enum Font {
        static let cardTitle = SwiftUI.Font.system(size: 17, weight: .semibold, design: .default)
        static let headerTitle = SwiftUI.Font.system(size: 24, weight: .semibold, design: .default)
        static let body = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        static let mono = SwiftUI.Font.system(size: 12, weight: .medium, design: .monospaced)
        static let monoLabel = SwiftUI.Font.system(size: 10, weight: .medium, design: .monospaced)
    }
}
