// Dark macOS design tokens for the plain HiBoss interface.
// Exports: DesignTokens colors, priority accents, and radius constants.
// Dependencies: SwiftUI Color and CGFloat.

import SwiftUI

enum DesignTokens {
    static let ink = Color(hex: 0xECEBE7)
    static let ink2 = Color(hex: 0xA7A6A0)
    static let ink3 = Color(hex: 0x7A7974)
    static let ink4 = Color(hex: 0x54534F)

    static let paper = Color(hex: 0x161614)
    static let surface = Color(hex: 0x1E1E1C)
    static let surface2 = Color(hex: 0x262624)
    static let surface3 = Color(hex: 0x2F2F2C)

    static let line = Color(hex: 0x2C2C29)
    static let line2 = Color(hex: 0x3A3A36)

    static let pos = Color(hex: 0x5E7257)
    static let neg = Color(hex: 0x97574B)
    static let warn = Color(hex: 0x9A7B43)
    static let statusLight = Color(hex: 0x6E8A5E)
    static let avatarTile = Color(hex: 0x26221F)

    enum Priority {
        static let critical = Color(hex: 0xC46A5A)
        static let high = Color(hex: 0xC79A57)
        static let normal = Color(hex: 0x7A7974)
        static let low = Color(hex: 0x54534F)
    }

    enum Radius {
        static let control: CGFloat = 6
        static let segment: CGFloat = 8
        static let row: CGFloat = 11
        static let window: CGFloat = 14
    }
}

private extension Color {
    init(hex rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }
}
