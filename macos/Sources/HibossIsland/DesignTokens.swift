// Semantic accents for the macOS client; everything else uses AppKit system colors.
// Exports: DesignTokens priority accents and the live-connection tint.
// Dependencies: SwiftUI Color bridged from NSColor.

import AppKit
import SwiftUI

/// Deliberately small. A token here must earn its place by having **no** system equivalent.
///
/// Anything with a system equivalent uses it directly at the call site — `Color.primary`,
/// `.secondary`, `Color(nsColor: .controlBackgroundColor)`, `Color(nsColor: .separatorColor)`,
/// `.background(.regularMaterial)`. A hardcoded palette is what made the previous pass read
/// as a web page in a window: it ignored the user's appearance, accent colour and contrast
/// settings, so a light system title bar sat on top of a near-black body.
///
/// Priority accents are the exception — they carry meaning the system has no colour for.
/// They resolve per appearance so they stay legible in both light and dark.
enum DesignTokens {
    enum Priority {
        static let critical = adaptive(light: 0x9E4634, dark: 0xE08A76)
        static let high = adaptive(light: 0x8A6520, dark: 0xD9AE66)
        static let normal = Color.secondary
        static let low = Color(nsColor: .tertiaryLabelColor)
    }

    /// The live/connected pulse. Distinct from `.green`, which reads as a system success badge.
    static let live = adaptive(light: 0x4A7A3F, dark: 0x7FBF6E)

    /// Corner radii for the few surfaces AppKit does not shape for us — the avatar tile and
    /// inline notices. Native `List` rows and `Form` sections shape themselves; do not reach
    /// for these to rebuild something the system already draws.
    enum Radius {
        static let tile: CGFloat = 6
        static let notice: CGFloat = 8
    }

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
