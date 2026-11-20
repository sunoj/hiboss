// Working sessions and recent deliveries from the shared Today snapshot.
// Exports: TodayActivity with session navigation, freshness, and full attachments.
// Dependencies: SwiftUI, HibossKit, and MessageAttachmentView.

import HibossKit
import SwiftUI

struct TodayActivity: View {
    @Environment(\.projectSessions) private var inventory
    let snapshot: TodaySnapshot
    let now: Date
    let onSession: (String) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            if !snapshot.working.isEmpty {
                group(Text(L("Working now"))) {
                    ForEach(Array(snapshot.working.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Divider().padding(.leading, 12) }
                        Button { onSession(session.id) } label: { sessionRow(session) }
                            .buttonStyle(.plain)
                    }
                }
            }
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

    private func deliveredRow(_ message: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onSession(SessionGrouping.sessionKey(for: message)) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.body).font(.body).foregroundStyle(.primary)
                    Text([message.sessionLabel, message.agentName].compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.caption).foregroundStyle(TodayStyle.secondary)
                    Text(HistoryTimestamp.localDateTime(from: message.createdAt))
                        .font(.caption).foregroundStyle(TodayStyle.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if let attachment = message.metadata?.attachment {
                MessageAttachmentView(attachment: attachment)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sessionRow(_ session: TodaySession) -> some View {
        let fact = inventory.first { $0.id == session.id }
        let project = fact?.avatarProject ?? ProjectIdentity(id: session.id,
            slug: session.projectLabel, displayName: session.projectLabel)
        return HStack(alignment: .top, spacing: 12) {
            ProjectAvatarView(project: project, size: 32)
            if let agent = session.agentName { AgentAvatarView(name: agent, size: 24) }
            VStack(alignment: .leading, spacing: 4) {
                Text(fact?.namedLabel
                    ?? [session.projectLabel, session.branch].compactMap { $0 }.joined(separator: " · "))
                    .font(.headline).foregroundStyle(.primary)
                Text(session.statusText).font(.callout).foregroundStyle(TodayStyle.secondary).lineLimit(2)
                if let agent = session.agentName {
                    Text(agent).font(.caption).foregroundStyle(TodayStyle.live)
                }
                if let updated = session.lastActivityDate {
                    TimelineView(.periodic(from: now, by: 1)) { context in
                        let age = AttentionClock.elapsed(since: updated, now: context.date)
                        Text(L("updated \(age) ago")).font(.caption).foregroundStyle(TodayStyle.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TodayStyle.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
