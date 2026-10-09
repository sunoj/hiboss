// Today working sessions and delivered messages with their attachment previews.
// Exports TodayResults, using the shared projection without sorting.
// Dependencies: SwiftUI, HibossKit, SessionRoute, MessageAttachmentView, and Theme.

import HibossKit
import SwiftUI

struct TodayResults: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !snapshot.working.isEmpty {
                section(Text("Working now")) {
                    ForEach(snapshot.working) { session in
                        NavigationLink(value: SessionRoute(id: session.id, label: session.projectLabel)) {
                            sessionRow(session)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !snapshot.delivered.isEmpty {
                section(Text("Delivered")) {
                    ForEach(snapshot.delivered) { message in
                        deliveredRow(message)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func section<Content: View>(
        _ title: Text, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title.font(.title3.bold())
            content()
        }
    }

    private func sessionRow(_ session: TodaySession) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: String(session.projectLabel.prefix(2)).uppercased())
                .font(.footnote.bold()).foregroundStyle(Theme.live)
                .frame(width: 40, height: 40)
                .background(Theme.liveSoft, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: [session.projectLabel, session.branch, session.agentName]
                    .compactMap { $0 }.joined(separator: " · ")).font(.subheadline.bold())
                Text(verbatim: session.statusText).font(.footnote).foregroundStyle(Theme.ink2)
                if let date = session.lastActivityDate {
                    Text(date, style: .relative).font(.caption).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func deliveredRow(_ message: HistoryMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let attachment = message.metadata?.attachment {
                MessageAttachmentView(attachment: attachment)
                    .frame(width: 72, height: 72).clipped()
            }
            NavigationLink(value: message.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: message.body).font(.subheadline.weight(.semibold))
                    Text(verbatim: message.metaLine).font(.footnote).foregroundStyle(Theme.ink2)
                    if let date = message.createdDate {
                        Text(date, style: .relative).font(.caption).foregroundStyle(Theme.ink3)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
        }
        .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}
