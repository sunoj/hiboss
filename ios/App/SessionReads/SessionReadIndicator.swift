// Renders a stable session attention/unread slot and provides the list read-state environment.
// Exports SessionReadIndicator and read-state environments; needs-you takes priority over unread,
// and a needs-you session with a live deadline shows DecisionCountdownRing instead of the dot.
// Dependencies: SwiftUI and Theme semantic attention, blue unread and green working roles.

import HibossKit
import SwiftUI

enum SessionIndicatorState: Equatable {
    case needsYou, unread, none

    init(needsYou: Bool, unread: Bool) {
        self = needsYou ? .needsYou : unread ? .unread : .none
    }
}

private struct UnreadSessionIDsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

private struct NeedsYouSessionIDsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    var unreadSessionIDs: Set<String> {
        get { self[UnreadSessionIDsKey.self] }
        set { self[UnreadSessionIDsKey.self] = newValue }
    }

    var needsYouSessionIDs: Set<String> {
        get { self[NeedsYouSessionIDsKey.self] }
        set { self[NeedsYouSessionIDsKey.self] = newValue }
    }
}

struct SessionReadIndicator: View {
    let sessionID: String
    let needsYou: Bool
    /// The open decision's timeout window; a live one turns the needs-you dot into a ring.
    var window: DecisionWindow? = nil
    @Environment(\.unreadSessionIDs) private var unread

    private var state: SessionIndicatorState {
        SessionIndicatorState(needsYou: needsYou, unread: unread.contains(sessionID))
    }

    var body: some View {
        if state == .needsYou, let window {
            DecisionCountdownRing(window: window)
                .accessibilityIdentifier("session-needs-you-\(sessionID)")
        } else {
            dot
        }
    }

    private var dot: some View {
        ZStack {
            if state != .none {
                Circle().fill(state == .needsYou ? Theme.warn : Theme.unread)
                    .accessibilityLabel(Text(verbatim: state == .needsYou
                        ? String(localized: "Needs you") : String(localized: "Unread")))
                    .accessibilityIdentifier(
                        "session-\(state == .needsYou ? "needs-you" : "unread")-\(sessionID)"
                    )
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(state == .none)
    }
}
