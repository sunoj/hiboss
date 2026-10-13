// Native color tokens backed by the design-v4 light and dark asset variants.
// Exports: Theme tokens (ink/surface/line) plus priority accents.
// Dependencies: SwiftUI, UIKit semantic colors, and the app asset catalog.

import SwiftUI
import UIKit
import HibossKit

/// Text stays semantic; named assets carry the design-v4 surface and state roles.
enum Theme {
    // Text
    static let ink = Color(.label)
    static let ink2 = Color("SecondaryText")
    static let ink3 = Color("TertiaryText")
    static let ink4 = Color(.quaternaryLabel)

    // Surfaces (grouped, so List/Form insets read correctly)
    static let paper = Color("Ground")
    static let surface = Color("Surface")
    static let surface2 = Color(.tertiarySystemFill)
    static let surface3 = Color(.systemFill)

    // Separators
    static let line = Color("Hairline")
    static let line2 = Color(.opaqueSeparator)

    // System tint and media surfaces
    static let accent = Color.accentColor
    static let link = Color(.link)
    static let unread = Color(uiColor: .systemBlue)
    static let onAccent = Color(uiColor: .systemBackground)
    static let mediaBackground = Color(.systemBackground)

    static let primaryAction = Color("Ink")
    static let live = Color("Live")
    static let liveSoft = Color("LiveSoft")
    static let signalSoft = Color("SignalSoft")
    static let settledSoft = Color("SettledSoft")

    // Status accents
    static let positive = Color("Settled")
    static let negative = Color.red
    static let warn = Color("Signal")
}

extension View {
    func prominentAction() -> some View {
        modifier(ProminentActionModifier(labelColor: Theme.onAccent))
    }
}

/// Message priority accents using system semantic colors.
enum PriorityColor {
    static let critical = Color.red
    static let high = Color.orange
    static let normal = Color(.systemGray)
    static let low = Color(.systemGray2)
    static let criticalText = Color.red
    static let highText = Color.orange
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
