// Details beneath a message's decision: who asked, where, when; routing facts collapsed.
// Exports: MessageDetailsCard.
// Dependencies: SwiftUI, HibossKit HistoryMessage, AttributeRow, MessageMeta, Theme.

import HibossKit
import SwiftUI

struct MessageDetailsCard: View {
    let message: HistoryMessage
    @State private var showsMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").hbLabel().foregroundStyle(Theme.ink2)
            VStack(alignment: .leading, spacing: 12) {
                primaryRows
                Divider()
                DisclosureGroup(isExpanded: $showsMore) {
                    VStack(alignment: .leading, spacing: 12) { moreRows }
                        .padding(.top, 12)
                } label: {
                    Text("More information").frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("message-more-information")
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder private var primaryRows: some View {
        AttributeRow(icon: "cpu", label: "Agent") {
            Text(verbatim: message.displayName)
        }
        if let session = trimmed(message.sessionLabel) {
            AttributeRow(icon: "square.stack.3d.up", label: "Session") {
                Text(verbatim: session)
            }
        }
        if let branch = trimmed(message.sessionBranch) {
            AttributeRow(icon: "arrow.triangle.branch", label: "Branch") {
                Text(verbatim: branch).monospaced()
            }
        }
        if !message.relativeCreatedAt.isEmpty {
            AttributeRow(icon: "clock", label: "Asked") {
                Text(verbatim: message.relativeCreatedAt)
            }
        }
        let p = MessageAttributeStyle.priority(message.priority)
        AttributeRow(icon: p.icon, tint: p.tint, label: "Priority") {
            Text(verbatim: MessageMeta.localizedPriorityName(message.priority))
        }
        let files = message.metadata?.files ?? []
        if !files.isEmpty {
            AttributeRow(icon: "doc.text", label: "Files") {
                Text(verbatim: files.map { $0.split(separator: "/").last.map(String.init) ?? $0 }.joined(separator: ", "))
            }
        }
    }

    @ViewBuilder private var moreRows: some View {
        AttributeRow(icon: MessageAttributeStyle.directionIcon(message.direction), label: "Direction") {
            Text(verbatim: MessageAttributeStyle.directionLabel(message.direction))
        }
        let glyph = MessageMeta.typeGlyph(message.type)
        AttributeRow(icon: glyph.icon, label: "Type") {
            Text(verbatim: glyph.label)
        }
        if let mode = trimmed(message.mode) {
            AttributeRow(icon: MessageAttributeStyle.mode(mode), label: "Mode") {
                Text(verbatim: MessageMeta.localizedModeName(mode))
            }
        }
        if let channel = trimmed(message.channel) {
            AttributeRow(icon: MessageAttributeStyle.channel(channel), label: "Channel") {
                Text(verbatim: channel.capitalized)
            }
        }
        let status = MessageAttributeStyle.status(message.status)
        AttributeRow(icon: status.icon, tint: status.tint, label: "Status") {
            Text(verbatim: MessageMeta.localizedStatusName(message.status))
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
