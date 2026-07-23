// Native color tokens mapped to system semantic colors (light + dark automatic).
// Exports: Theme tokens (ink/surface/line) plus priority accents.
// Dependencies: SwiftUI, UIKit semantic colors.

import SwiftUI
import UIKit

/// Semantic tokens. Names kept for source compatibility; values are now the
/// system's dynamic colors so the app reads as native iOS, not a web palette.
enum Theme {
    // Text
    static let ink = Color(.label)
    static let ink2 = Color(.secondaryLabel)
    static let ink3 = Color(.tertiaryLabel)
    static let ink4 = Color(.quaternaryLabel)

    // Surfaces (grouped, so List/Form insets read correctly)
    static let paper = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let surface2 = Color(.tertiarySystemFill)
    static let surface3 = Color(.systemFill)

    // Separators
    static let line = Color(.separator)
    static let line2 = Color(.opaqueSeparator)

    // Status accents
    static let positive = Color.green
    static let negative = Color.red
    static let warn = Color.orange
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
