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

    @Environment(\.dynamicTypeSize) private var typeSize

    private var projectName: String { identity?.label ?? session.localizedLabel }

    private var caption: String {
        [session.branch ?? identity?.branch, session.agentName ?? identity?.agentName]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            ProjectAvatarView(project: identity?.avatarProject ?? .fallback(session.localizedLabel),
                              size: AvatarSize.row)
            VStack(alignment: .leading, spacing: Space.xxs) {
                // The time sits beside the name only while the whole name fits; otherwise it moves below.
                if typeSize.isAccessibilitySize {
                    stackedTitle
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xs) { nameLine; timeText }
                        stackedTitle
                    }
                }
                Text(verbatim: session.statusText).font(.subheadline).foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                HStack(spacing: Space.xxs) {
                    if let agent = session.agentName {
                        AgentAvatarView(name: agent, size: AvatarSize.inline)
                    }
                    Text(verbatim: caption).font(.caption).foregroundStyle(Theme.ink2)
                        .lineLimit(1).truncationMode(.tail)
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

    private var stackedTitle: some View {
        VStack(alignment: .leading, spacing: Space.xxs) { nameLine; timeText }
    }

    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: projectName).font(.headline)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Spacer(minLength: Space.xxs)
            SessionReadIndicator(sessionID: session.id, needsYou: session.needsYou)
        }
    }

    @ViewBuilder private var timeText: some View {
        if let date = session.lastActivityDate {
            RecordedTimeText(date: date).font(.caption).foregroundStyle(Theme.ink3).fixedSize()
        }
    }
}
