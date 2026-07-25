// Attribute-row styling for the message detail Details section.
// Exports: MessageAttributeStyle, AttributeRow, MessageDetailsSection.
// Dependencies: SwiftUI, HibossKit HistoryMessage, CountdownText.

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
        case "agent_to_boss": "Agent → Boss"
        case "boss_to_agent": "Boss → Agent"
        case "agent_to_agent": "Agent → Agent"
        default: raw
        }
    }

    static func priority(_ raw: String) -> (icon: String, tint: Color) {
        switch raw.lowercased() {
        case "critical": ("exclamationmark.octagon.fill", .red)
        case "high": ("exclamationmark.triangle.fill", .orange)
        case "low": ("arrow.down.circle", .secondary)
        default: ("equal.circle", .secondary)
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
        case "delivered": ("checkmark.circle.fill", .green)
        case "read": ("eye.fill", .blue)
        case "sent": ("paperplane.fill", .secondary)
        case "queued", "pending": ("clock.badge", .orange)
        case "expired": ("clock.badge.xmark", .secondary)
        case "failed": ("exclamationmark.circle.fill", .red)
        default: ("circle", .secondary)
        }
    }
}

struct AttributeRow<Value: View>: View {
    let icon: String
    var tint: Color = .secondary
    let label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        LabeledContent {
            value()
        } label: {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
        }
    }
}

struct MessageDetailsSection: View {
    let message: HistoryMessage

    var body: some View {
        Section("Details") {
            baseRows
            optionalRows
            statusRow
        }
    }

    @ViewBuilder private var baseRows: some View {
        AttributeRow(icon: "cpu", label: "Agent") {
            Text(message.displayName)
        }
        if let session = message.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !session.isEmpty {
            AttributeRow(icon: "square.stack.3d.up", label: "Session") {
                Text(session)
            }
        }
        AttributeRow(icon: MessageAttributeStyle.directionIcon(message.direction), label: "Direction") {
            Text(MessageAttributeStyle.directionLabel(message.direction))
        }
        let p = MessageAttributeStyle.priority(message.priority)
        AttributeRow(icon: p.icon, tint: p.tint, label: "Priority") {
            Text(message.priority.capitalized)
        }
    }

    @ViewBuilder private var optionalRows: some View {
        if let mode = message.mode, !mode.isEmpty {
            AttributeRow(icon: MessageAttributeStyle.mode(mode), label: "Mode") {
                Text(mode.capitalized)
            }
        }
        if let channel = message.channel, !channel.isEmpty {
            AttributeRow(icon: MessageAttributeStyle.channel(channel), label: "Channel") {
                Text(channel.capitalized)
            }
        }
        if message.isPendingDecision, let deadline = message.expirationDate {
            let tint: Color = message.priorityValue == .critical ? .red : .secondary
            AttributeRow(icon: "timer", tint: tint, label: "Time left") {
                CountdownText(deadline: deadline, tint: tint)
            }
        }
        if !message.relativeCreatedAt.isEmpty {
            AttributeRow(icon: "clock", label: "Created") {
                Text(message.relativeCreatedAt)
            }
        }
    }

    private var statusRow: some View {
        let s = MessageAttributeStyle.status(message.status)
        return AttributeRow(icon: s.icon, tint: s.tint, label: "Status") {
            Text(message.status.capitalized)
        }
    }
}
