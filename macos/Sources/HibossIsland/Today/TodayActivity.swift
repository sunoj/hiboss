// Recent deliveries from the shared Today snapshot; working sessions live in the sidebar.
// Exports: TodayActivity: compact delivered rows that open their session.
// Dependencies: SwiftUI, HibossKit, AttentionItem provenance, and SharedTimestamp.

import HibossKit
import SwiftUI

struct TodayActivity: View {
    @Environment(\.projectSessions) private var inventory
    let snapshot: TodaySnapshot
    let now: Date
    let onSession: (String) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if !snapshot.delivered.isEmpty {
                group(Text(L("Delivered"))) {
                    ForEach(Array(snapshot.delivered.enumerated()), id: \.element.id) { index, message in
                        if index > 0 { Divider().padding(.leading, 12) }
                        deliveredRow(message)
                    }
                }
            }
        }
    }

    /// One surface per section. The headline stays outside the card, matching the Mac type scale.
    private func group<Content: View>(_ title: Text, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title.font(.headline).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { rows() }
                .background(TodayStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// One line of what shipped, who and where, with the time at the trailing edge.
    private func deliveredRow(_ message: HistoryMessage) -> some View {
        let item = AttentionItem(message: message, group: .priority)
        let project = item.project(in: inventory)
        return VStack(alignment: .leading, spacing: 4) {
            Button { onSession(SessionGrouping.sessionKey(for: message)) } label: {
                HStack(alignment: .top, spacing: 12) {
                    ProjectAvatarView(project: project, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.body).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                        Text(verbatim: item.provenance(project: project.displayName))
                            .font(.caption).foregroundStyle(TodayStyle.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let date = ISODate.parse(message.createdAt) {
                        TimelineView(.periodic(from: .now, by: 60)) { tick in
                            Text(SharedTimestamp.string(date, now: tick.date))
                                .font(.caption).foregroundStyle(TodayStyle.tertiary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            // A row stays one line high; the session shows the attachment itself.
            if let attachment = message.metadata?.attachment {
                Label(attachment.filename, systemImage: "paperclip")
                    .font(.caption).foregroundStyle(TodayStyle.secondary).lineLimit(1)
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
