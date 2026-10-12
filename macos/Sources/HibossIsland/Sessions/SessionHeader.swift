// Native session identity and live step strip with timestamped connection evidence.
// Exports: SessionHeader; absent inventory facts are omitted.
// Dependencies: SwiftUI, HibossKit, SessionContext, and design-v4 colours.

import HibossKit
import SwiftUI

struct SessionHeader: View {
    let context: SessionContext
    let connection: ConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ProjectAvatarView(project: context.avatarProject, size: 40)
                Text(context.branch ?? L("Session activity")).font(.title2.bold())
                    .accessibilityAddTraits(.isHeader).layoutProbe("session.title")
                Spacer()
            }
            HStack(spacing: 12) {
                if let agent = context.facts?.agentName {
                    HStack(spacing: 4) {
                        AgentAvatarView(name: agent, size: 20)
                        Text(verbatim: agent)
                    }
                }
                if let host = context.facts?.host { Label(host, systemImage: "desktopcomputer") }
            }.font(.callout).foregroundStyle(TodayStyle.secondary)
            step
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(TodayStyle.surface)
        .accessibilityIdentifier("session.header")
    }

    private var step: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text = context.facts?.statusText {
                Text(text).font(.callout).textSelection(.enabled)
            }
            HStack {
                Label(connection.label, systemImage: connection == .connected
                    ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                if let status = context.facts?.status { Text(verbatim: status) }
                Spacer(minLength: 4)
                if let date = context.facts?.lastSeenAt.flatMap(ISODate.parse) {
                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        Text(L("Updated \(AttentionClock.elapsed(since: date, now: tick.date)) ago"))
                    }
                }
            }.font(.caption).foregroundStyle(TodayStyle.secondary)
        }
        .padding(10).background(TodayStyle.liveSoft, in: RoundedRectangle(cornerRadius: 6))
    }
}
