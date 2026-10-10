// Semantic accents backed by the design-v4 named colour resources.
// Exports: DesignTokens category/priority accents and the live-connection tint.
// Dependencies: SwiftUI Color bridged from NSColor.

import AppKit
import SwiftUI

enum DesignTokens {
    enum Priority {
        static let critical = TodayStyle.signal
        static let high = TodayStyle.signal
        static let normal = Color.secondary
        static let low = Color(nsColor: .tertiaryLabelColor)
    }

    /// Healthy connection; working sessions use the Live role instead.
    static let live = TodayStyle.settled

    /// Corner radii for the few surfaces AppKit does not shape for us — the avatar tile and
    /// inline notices. Native `List` rows and `Form` sections shape themselves; do not reach
    /// for these to rebuild something the system already draws.
    enum Radius {
        static let tile: CGFloat = 6
        static let notice: CGFloat = 8
    }

}
