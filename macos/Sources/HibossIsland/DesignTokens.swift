// Shared visual tokens for the macOS dark design language.
// Exports: DesignTokens colors, radii, and typography helpers.
// Dependencies: SwiftUI Color and Font.

import SwiftUI

enum DesignTokens {
    enum Colors {
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
        static let critical = Color(hex: 0xC46A5A)
        static let high = Color(hex: 0xC79A57)
        static let normal = Color(hex: 0x7A7974)
        static let low = Color(hex: 0x54534F)
        static let live = Color(hex: 0x6E8A5E)
        static let liveInner = Color(hex: 0x8FB07E)
        static let avatarTile = Color(hex: 0x26221F)
    }

    enum Radius {
        static let control: CGFloat = 6
        static let pill: CGFloat = 8
        static let row: CGFloat = 11
        static let window: CGFloat = 14
    }

    enum Fonts {
        static let paneTitle = Font.system(size: 18, weight: .semibold)
        static let sectionHeader = Font.system(size: 13, weight: .semibold)
        static let rowTitle = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let caption = Font.system(size: 12, weight: .regular)
        static let monoLabel = Font.system(size: 11, weight: .medium).monospaced()
    }
}

private extension Color {
    init(hex: Int) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
