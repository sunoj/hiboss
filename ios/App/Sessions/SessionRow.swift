// Two-line session row: "project / branch" with its time, then status · agent.
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

    /// The branch after the name; a default branch, or one the label already names, is not repeated.
    private var branchSuffix: String? {
        guard let branch = session.branch ?? identity?.branch, !branch.isEmpty,
              !["main", "master"].contains(branch.lowercased()), !projectName.contains(branch) else { return nil }
        return " / " + branch
    }

    /// The project stays whole; the branch, in secondary ink, is what truncates.
    private var title: Text {
        Text(verbatim: projectName) + Text(verbatim: branchSuffix ?? "").foregroundColor(Theme.ink3)
    }

    /// One line under the name: what the session is doing, then who is doing it.
    private var subtitle: String {
        [session.statusText, session.agentName ?? identity?.agentName ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            ProjectAvatarView(project: identity?.avatarProject ?? .fallback(session.localizedLabel),
                              size: AvatarSize.row)
            VStack(alignment: .leading, spacing: Space.xxs) {
                if typeSize.isAccessibilitySize {
                    stackedTitle
                } else {
                    // One line: the branch truncates first so the time always fits.
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) { nameLine; timeText }
                }
                Text(verbatim: subtitle).font(.subheadline).foregroundStyle(Theme.ink2)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
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
            title.font(.headline)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            Spacer(minLength: Space.xxs)
            SessionReadIndicator(sessionID: session.id, needsYou: session.needsYou,
                                 window: session.decisionWindow)
        }
    }

    @ViewBuilder private var timeText: some View {
        if let date = session.lastActivityDate {
            RecordedTimeText(date: date).font(.caption).foregroundStyle(Theme.ink3).fixedSize()
        }
    }
}
