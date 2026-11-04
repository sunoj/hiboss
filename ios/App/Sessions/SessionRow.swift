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

    private var identity: ProjectSession? { inventory.first { $0.id == session.id } }

    private var label: String {
        identity?.namedLabel ?? [session.localizedLabel, session.branch].compactMap { $0 }
            .joined(separator: " / ")
    }

    private var title: some View {
        HStack(spacing: 0) {
            if label.hasPrefix(session.localizedLabel), label != session.localizedLabel {
                Text(verbatim: session.localizedLabel).minimumScaleFactor(0.5).layoutPriority(1)
                Text(verbatim: String(label.dropFirst(session.localizedLabel.count)))
                    .truncationMode(.middle)
            } else {
                Text(verbatim: label).truncationMode(.middle)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            ProjectAvatarView(project: identity?.avatarProject ?? .fallback(session.localizedLabel),
                              size: AvatarSize.row)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    title.font(.headline).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                    Spacer(minLength: Space.xxs)
                    SessionReadIndicator(sessionID: session.id, needsYou: session.needsYou)
                    if let date = session.lastActivityDate {
                        RecordedTimeText(date: date).font(.caption).foregroundStyle(Theme.ink3)
                            .fixedSize()
                    }
                }
                Text(verbatim: session.statusText).font(.subheadline).foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                HStack(spacing: Space.xxs) {
                    if let agent = session.agentName {
                        AgentAvatarView(name: agent, size: AvatarSize.inline)
                        Text(verbatim: agent).font(.caption).foregroundStyle(Theme.ink2)
                    }
                    if session.hasLiveWork(now: .now) && !session.needsYou {
                        Text("Working").font(.caption).foregroundStyle(Theme.positive)
                    }
                }
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
