// Native session list summary: session, status, agent and latest activity.
// Exports: SessionRow and TodaySession localization for Activity.
// Dependencies: SwiftUI, HibossKit TodaySession and Theme.

import HibossKit
import SwiftUI

extension TodaySession {
    var localizedLabel: String {
        id == SessionGrouping.directSessionID ? String(localized: "Direct") : projectLabel
    }
}

struct SessionRow: View {
    let session: TodaySession
    @Environment(\.projectSessions) private var inventory
    @Environment(\.dynamicTypeSize) private var typeSize

    private var identity: ProjectSession? { inventory.first { $0.id == session.id } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProjectAvatarView(project: identity?.avatarProject ?? .fallback(session.localizedLabel), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: identity?.namedLabel ?? [session.localizedLabel, session.branch]
                    .compactMap { $0 }.joined(separator: " / ")).font(.headline)
                Text(verbatim: session.statusText).font(.subheadline).foregroundStyle(Theme.ink2)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if let agent = session.agentName {
                    HStack(spacing: 4) {
                        AgentAvatarView(name: agent, size: 22)
                        Text(verbatim: agent).font(.caption).foregroundStyle(Theme.ink2)
                    }
                }
                if let date = session.lastActivityDate {
                    RecordedTimeText(date: date).font(.caption).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                SessionReadIndicator(sessionID: session.id, needsYou: session.needsYou)
                if session.hasLiveWork(now: .now) && !session.needsYou {
                    Text("Working").font(.caption).foregroundStyle(Theme.positive)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
