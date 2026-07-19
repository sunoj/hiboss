// Design-system color tokens ported from the "plain" HiBoss foundations.
// Exports: Theme color tokens (ink/surface/line) plus fixed accent/status colors.
// Dependencies: SwiftUI, UIKit dynamic colors for light/dark resolution.

import SwiftUI
import UIKit

/// Resolves to different values in light and dark, matching colors_and_type.css.
private func dyn(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
    })
}

private func fixed(_ rgb: UInt32) -> Color { Color(uiColor: UIColor(rgb: rgb)) }

enum Theme {
    // Ink (text)
    static let ink = dyn(light: 0x1B1B1A, dark: 0xECEBE7)
    static let ink2 = dyn(light: 0x5C5B57, dark: 0xA7A6A0)
    static let ink3 = dyn(light: 0x8A8984, dark: 0x7A7974)
    static let ink4 = dyn(light: 0xB3B2AC, dark: 0x54534F)

    // Surfaces
    static let paper = dyn(light: 0xF6F5F3, dark: 0x161614)
    static let surface = dyn(light: 0xFFFFFF, dark: 0x1E1E1C)
    static let surface2 = dyn(light: 0xEFEEEB, dark: 0x262624)
    static let surface3 = dyn(light: 0xE7E5E1, dark: 0x2F2F2C)

    // Lines
    static let line = dyn(light: 0xE4E2DD, dark: 0x2C2C29)
    static let line2 = dyn(light: 0xD5D3CD, dark: 0x3A3A36)

    // Status / accents (fixed across themes — used as small accents)
    static let positive = fixed(0x5E7257)
    static let negative = fixed(0x97574B)
    static let warn = fixed(0x9A7B43)
}

/// Message priority accent colors from the design canvas legend.
enum PriorityColor {
    static let critical = fixed(0xC46A5A)
    static let high = fixed(0xC79A57)
    static let normal = fixed(0x7A7974)
    static let low = fixed(0x54534F)
    /// Lifted tint used for badge/label text so it reads on both themes.
    static let criticalText = fixed(0xD08475)
    static let highText = fixed(0xCBA766)
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
