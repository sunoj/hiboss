// Type ramp mapped to native Dynamic Type text styles (scales with the user's
// preferred size). Names kept for source compatibility.
// Dependencies: SwiftUI.

import SwiftUI

extension Font {
    static let hbLargeTitle = Font.largeTitle.weight(.bold)
    static let hbH2 = Font.title2.weight(.semibold)
    static let hbH3 = Font.headline
    static let hbBody = Font.body
    static let hbBodyStrong = Font.body.weight(.semibold)
    static let hbCallout = Font.callout
    static let hbSmall = Font.subheadline
    static let hbCaption = Font.caption
    static let hbFootnote = Font.footnote

    static let hbMono = Font.system(.footnote, design: .monospaced)
    static let hbMonoSmall = Font.system(.caption2, design: .monospaced)
}

/// The quiet uppercase "label" role, as a footnote-scale tracked caption.
struct HBLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.footnote.weight(.medium))
            .tracking(0.4)
            .textCase(.uppercase)
    }
}

extension View {
    func hbLabel() -> some View { modifier(HBLabel()) }
}
