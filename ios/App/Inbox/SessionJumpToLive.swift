// "Jump to live" on a scrolled-away transcript: a pill above the composer, or an icon on a side rail.
// Exports JumpToLiveButton; both forms share the label, the identifier and the action.
// Dependencies: SwiftUI, the app's Space and prominentAction styling.

import SwiftUI

struct JumpToLiveButton: View {
    /// Events that arrived while the reader was scrolled away.
    let pending: Int
    /// The rail form: a toolbar icon, which the Duo draws on its side rail.
    let onRail: Bool
    let action: () -> Void

    private var title: String {
        pending > 0 ? String(localized: "Jump to live (\(pending))") : String(localized: "Jump to live")
    }

    var body: some View {
        if onRail {
            Button(action: action) {
                Image(systemName: "arrow.up.to.line")
                    .frame(minWidth: ControlMetric.minTap, minHeight: ControlMetric.minTap)
                    .overlay(alignment: .topTrailing) {
                        if pending > 0 {
                            Text(verbatim: "\(pending)").font(.caption2.weight(.semibold)).monospacedDigit()
                        }
                    }
            }
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityIdentifier("jump-to-live")
        } else {
            Button(action: action) {
                Label { Text(verbatim: title) } icon: { Image(systemName: "arrow.up.to.line") }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs)
            }
            .prominentAction()
            .padding(.bottom, Space.s)
            .accessibilityIdentifier("jump-to-live")
        }
    }
}
