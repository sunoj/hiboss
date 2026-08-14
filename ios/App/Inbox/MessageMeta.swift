// Single catalog of message type/priority/mode/channel/file glyphs.
// Exports: MessageMeta density items, MessageMetaStrip, and option swipe icons.
// Dependencies: SwiftUI, HibossKit HistoryMessage.

import HibossKit
import SwiftUI

enum MessageMeta {
    enum Density { case row, selected, detail }

    /// Row: notable type, urgent priority, blocking. Selected adds mode/channel/files.
    /// Detail is the full labeled set for the message sheet.
    static func items(for message: HistoryMessage, density: Density) -> [MessageMetaItem] {
        switch density {
        case .row: return rowItems(for: message)
        case .selected: return selectedItems(for: message)
        case .detail: return selectedItems(for: message)
        }
    }

    static func typeGlyph(_ raw: String?) -> (icon: String, label: String) {
        switch (raw ?? "").lowercased() {
        case "task_update": return ("checkmark.seal", String(localized: "Update"))
        case "approval_request": return ("checkmark.shield", String(localized: "Approval"))
        case "steer_command": return ("arrow.turn.up.right", String(localized: "Steer"))
        case "forwarded": return ("arrowshape.turn.up.forward", String(localized: "Forwarded"))
        case "text", "": return ("text.bubble", String(localized: "Message"))
        default:
            let label = (raw ?? String(localized: "Message")).replacingOccurrences(of: "_", with: " ").capitalized
            return ("tag", label)
        }
    }

    static func localizedPriorityName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "critical": String(localized: "Critical")
        case "high": String(localized: "High")
        case "normal": String(localized: "Normal")
        case "low": String(localized: "Low")
        default: raw.capitalized
        }
    }

    static func localizedModeName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "blocking": String(localized: "Blocking")
        case "async": String(localized: "Async")
        default: raw.capitalized
        }
    }

    static func localizedStatusName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "delivered": String(localized: "Delivered")
        case "read": String(localized: "Read")
        case "sent": String(localized: "Sent")
        case "queued": String(localized: "Queued")
        case "pending": String(localized: "Pending")
        case "replied": String(localized: "Replied")
        case "expired": String(localized: "Expired")
        case "failed": String(localized: "Failed")
        case "resolved": String(localized: "Resolved")
        default: raw.capitalized
        }
    }

    static func optionIcon(_ option: String) -> String {
        switch option.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approve", "yes", "ship", "provide": "checkmark"
        case "reject", "no", "hold", "later": "xmark"
        default: "circle"
        }
    }

    private static func rowItems(for message: HistoryMessage) -> [MessageMetaItem] {
        var items: [MessageMetaItem] = []
        let type = (message.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !type.isEmpty, type.lowercased() != "text" {
            let glyph = typeGlyph(type)
            items.append(MessageMetaItem(id: "type", icon: glyph.icon, label: glyph.label, value: glyph.label))
        }
        let priority = message.priorityValue
        if priority == .critical || priority == .high {
            let p = MessageAttributeStyle.priority(message.priority)
            items.append(MessageMetaItem(id: "priority", icon: p.icon, label: priority.localizedTitle, value: priority.localizedTitle, tint: p.tint))
        }
        if message.mode == "blocking" {
            items.append(MessageMetaItem(id: "mode", icon: MessageAttributeStyle.mode("blocking"), label: String(localized: "Blocking"), value: String(localized: "Blocking")))
        }
        return items
    }

    private static func selectedItems(for message: HistoryMessage) -> [MessageMetaItem] {
        var items = rowItems(for: message)
        if items.contains(where: { $0.id == "type" }) == false {
            let glyph = typeGlyph(message.type)
            items.insert(MessageMetaItem(id: "type", icon: glyph.icon, label: glyph.label, value: glyph.label), at: 0)
        }
        if items.contains(where: { $0.id == "priority" }) == false {
            let p = MessageAttributeStyle.priority(message.priority)
            items.append(MessageMetaItem(id: "priority", icon: p.icon, label: String(localized: "Priority"), value: localizedPriorityName(message.priority), tint: p.tint))
        }
        if let mode = message.mode, !mode.isEmpty, items.contains(where: { $0.id == "mode" }) == false {
            items.append(MessageMetaItem(id: "mode", icon: MessageAttributeStyle.mode(mode), label: String(localized: "Mode"), value: localizedModeName(mode)))
        }
        if let channel = message.channel, !channel.isEmpty {
            items.append(MessageMetaItem(id: "channel", icon: MessageAttributeStyle.channel(channel), label: String(localized: "Channel"), value: channel.capitalized))
        }
        let files = message.metadata?.files ?? []
        if !files.isEmpty {
            let name = files[0].split(separator: "/").last.map(String.init) ?? files[0]
            let value = files.count == 1 ? name : String(localized: "\(files.count) files")
            items.append(MessageMetaItem(id: "files", icon: "doc.text", label: String(localized: "Files"), value: value))
        }
        return items
    }
}

struct MessageMetaItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
    let value: String
    var tint: Color = .secondary
}

struct MessageMetaStrip: View {
    let message: HistoryMessage
    var density: MessageMeta.Density = .row

    var body: some View {
        let items = MessageMeta.items(for: message, density: density)
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { ForEach(items) { chip($0) } }
                HStack(spacing: 8) { ForEach(items.prefix(4)) { chip($0) } }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private func chip(_ item: MessageMetaItem) -> some View {
        if density == .row {
            Image(systemName: item.icon)
                .foregroundStyle(item.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("\(item.label) \(item.value)")
        } else {
            Label {
                Text(item.value)
            } icon: {
                Image(systemName: item.icon).foregroundStyle(item.tint)
            }
            .labelStyle(.titleAndIcon)
        }
    }
}
