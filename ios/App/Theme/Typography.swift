// Type ramp ported from the design foundations (plain hierarchy via size/weight).
// Exports: Font helpers and a monospaced tracked "label" modifier.
// Dependencies: SwiftUI. Uses the system faces (SF / SF Mono) as IBM Plex fallback.

import SwiftUI

extension Font {
    static let hbLargeTitle = Font.system(size: 32, weight: .semibold)
    static let hbH2 = Font.system(size: 22, weight: .semibold)
    static let hbH3 = Font.system(size: 17, weight: .medium)
    static let hbBody = Font.system(size: 16, weight: .regular)
    static let hbBodyStrong = Font.system(size: 16, weight: .semibold)
    static let hbCallout = Font.system(size: 15, weight: .regular)
    static let hbSmall = Font.system(size: 14, weight: .regular)
    static let hbCaption = Font.system(size: 13, weight: .regular)
    static let hbFootnote = Font.system(size: 13, weight: .regular)

    static let hbMono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let hbMonoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}

/// The mono "label" role: quiet, tracked, uppercase — the one bit of texture.
struct HBLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .tracking(0.6)
            .textCase(.uppercase)
    }
}

extension View {
    func hbLabel() -> some View { modifier(HBLabel()) }
}
