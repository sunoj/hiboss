// Navigation value for drilling from a message or list into a session's messages.
// Exports: SessionRoute.
// Dependencies: HibossKit HistoryMessage and SessionGrouping.

import Foundation
import HibossKit

/// Navigation value for drilling into a session's messages.
struct SessionRoute: Hashable {
    let id: String
    let label: String

    init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    init(message: HistoryMessage) {
        let id = SessionGrouping.sessionKey(for: message)
        let session = message.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = session.isEmpty
            ? (id == SessionGrouping.directSessionID ? message.displayName : String(id.prefix(8)))
            : session
        self.init(id: id, label: label)
    }
}
