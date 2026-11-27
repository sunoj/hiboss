// Renders independent attention/unread indicators and the live-work caption.
// Exports: SidebarSessionIndicator, SidebarWorkingCaption and SidebarSessionState (waiting/working/idle).
// Dependencies: SwiftUI, TodayStyle, and native semantic unread colour.

import HibossKit
import SwiftUI

enum SidebarSessionIndicator: Equatable {
    case needsYou, unread, none

    init(needsYou: Bool, unread: Bool) {
        self = needsYou ? .needsYou : unread ? .unread : .none
    }

    var label: String {
        switch self {
        case .needsYou: L("Needs You")
        case .unread: L("Unread")
        case .none: ""
        }
    }

    @MainActor func view(sessionID: String) -> some View {
        ZStack {
            if self != .none {
                Circle().fill(self == .needsYou ? TodayStyle.signal : Color(nsColor: .systemBlue))
                    .accessibilityLabel(label)
                    .layoutProbe("sidebar.\(self == .needsYou ? "needsYou" : "unread").\(sessionID)")
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(self == .none)
    }
}

struct SidebarWorkingCaption: View {
    @Environment(\.backgroundProminence) private var prominence

    /// Green on a plain row; an emphasized selected row keeps the selection's own foreground.
    static func usesStatusColor(_ prominence: BackgroundProminence) -> Bool {
        prominence != .increased
    }

    var body: some View {
        Text(L("Working"))
            .font(.caption).foregroundStyle(Self.usesStatusColor(prominence)
                ? AnyShapeStyle(TodayStyle.settled) : AnyShapeStyle(.secondary))
            .fixedSize().layoutPriority(1)
            .accessibilityLabel(L("Working now"))
    }
}

/// The second-line state after the agent: "· waiting 31s" for a session that needs the boss,
/// "Working" while it works, else how long ago it was last active.
struct SidebarSessionState: View {
    @Environment(\.surfaceIsVisible) private var isVisible
    let session: TodaySession
    let waitingSince: Date?
    let now: Date

    var body: some View {
        if let waitingSince {
            TimelineView(ElapsedLabelSchedule(since: waitingSince).paused(!isVisible)) { tick in
                Text(L("· waiting \(AttentionClock.elapsed(since: waitingSince, now: tick.date, coarse: true))"))
                    .font(.caption).foregroundStyle(TodayStyle.signal).lineLimit(1).fixedSize()
            }
        } else if session.hasLiveWork(now: now) {
            SidebarWorkingCaption().layoutProbe("sidebar.working.\(session.id)")
        } else if let last = session.lastActivityDate {
            Text(verbatim: "· " + AttentionClock.elapsed(since: last, now: now, coarse: true))
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
        }
    }
}
