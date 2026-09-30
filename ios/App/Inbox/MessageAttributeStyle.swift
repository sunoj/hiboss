// Attribute-row styling for the message detail Details card.
// Exports: MessageAttributeStyle and AttributeRow.
// Dependencies: SwiftUI and Theme tokens.

import HibossKit
import SwiftUI

enum MessageAttributeStyle {
    static func directionIcon(_ raw: String) -> String {
        switch raw {
        case "agent_to_boss": "arrow.up.forward"
        case "boss_to_agent": "arrow.down.backward"
        case "agent_to_agent": "arrow.left.arrow.right"
        default: "arrow.right"
        }
    }

    static func directionLabel(_ raw: String) -> String {
        switch raw {
        case "agent_to_boss": String(localized: "Agent → Boss")
        case "boss_to_agent": String(localized: "Boss → Agent")
        case "agent_to_agent": String(localized: "Agent → Agent")
        default: raw
        }
    }

    static func priority(_ raw: String) -> (icon: String, tint: Color) {
        switch raw.lowercased() {
        case "critical": ("exclamationmark.octagon.fill", Theme.negative)
        case "high": ("exclamationmark.triangle.fill", Theme.warn)
        case "low": ("arrow.down.circle", Theme.ink2)
        default: ("equal.circle", Theme.ink2)
        }
    }

    static func mode(_ raw: String) -> String {
        raw.lowercased() == "blocking" ? "hourglass" : "paperplane"
    }

    static func channel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "discord": "bubble.left.and.bubble.right.fill"
        case "telegram": "paperplane.circle.fill"
        case "api": "chevron.left.forwardslash.chevron.right"
        default: "dot.radiowaves.left.and.right"
        }
    }

    static func status(_ raw: String) -> (icon: String, tint: Color) {
        switch raw.lowercased() {
        case "delivered": ("checkmark.circle.fill", Theme.positive)
        case "read": ("eye.fill", Theme.accent)
        case "sent": ("paperplane.fill", Theme.ink2)
        case "queued", "pending": ("clock.badge", Theme.warn)
        case "expired": ("clock.badge.xmark", Theme.ink2)
        case "failed": ("exclamationmark.circle.fill", Theme.negative)
        default: ("circle", Theme.ink2)
        }
    }
}

struct AttributeRow<Value: View>: View {
    let icon: String
    var tint: Color = Theme.ink2
    /// Localized through the catalog; a plain String here would render verbatim.
    let label: LocalizedStringResource
    @ViewBuilder var value: () -> Value
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                labelView
                value().foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent {
                value().multilineTextAlignment(.trailing)
            } label: {
                labelView
            }
        }
    }

    private var labelView: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
    }
}
