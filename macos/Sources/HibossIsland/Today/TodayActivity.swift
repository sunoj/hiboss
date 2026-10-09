// Working sessions and recent deliveries from the shared Today snapshot.
// Exports: TodayActivity with session navigation, freshness, and full attachments.
// Dependencies: SwiftUI, HibossKit, and MessageAttachmentView.

import HibossKit
import SwiftUI

struct TodayActivity: View {
    let snapshot: TodaySnapshot
    let now: Date
    let onSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !snapshot.working.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Working now")).font(.headline)
                    ForEach(snapshot.working) { session in
                        Button { onSession(session.id) } label: { sessionRow(session) }
                            .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            if !snapshot.delivered.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Delivered")).font(.headline)
                    ForEach(snapshot.delivered) { message in
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
                        Divider()
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: TodaySession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(session.projectLabel.prefix(1)).uppercased()).font(.headline)
                .foregroundStyle(TodayStyle.live).frame(width: 32, height: 32)
                .background(TodayStyle.liveSoft, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text([session.projectLabel, session.branch].compactMap { $0 }.joined(separator: " · "))
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
        }
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
