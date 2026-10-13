// Renders a stable session attention/unread slot and provides the list read-state environment.
// Exports SessionReadIndicator and unreadSessionIDs; needs-you takes priority over unread.
// Dependencies: SwiftUI and Theme semantic attention, blue unread and green working roles.

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
    @Environment(\.unreadSessionIDs) private var unread

    private var state: SessionIndicatorState {
        SessionIndicatorState(needsYou: needsYou, unread: unread.contains(sessionID))
    }

    var body: some View {
        ZStack {
            if state != .none {
                Circle().fill(state == .needsYou ? Theme.warn : Theme.unread)
                    .accessibilityLabel(Text(verbatim: state == .needsYou
                        ? String(localized: "Needs you") : String(localized: "Unread")))
                    .accessibilityIdentifier("session-\(state == .needsYou ? "needs-you" : "unread")-\(sessionID)")
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityHidden(state == .none)
    }
}
