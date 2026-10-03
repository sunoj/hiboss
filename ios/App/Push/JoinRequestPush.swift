// APNs contract for "New device wants to join": category and payload → request ID.
// Exports: JoinRequestPush.
// Dependencies: UserNotifications.

import UserNotifications

/// The category deliberately has no actions: approving needs the code compared on screen first.
enum JoinRequestPush {
    static let category = "HIBOSS_JOIN_REQUEST"
    static let requestIDKey = "join_request_id"

    static func notificationCategory() -> UNNotificationCategory {
        UNNotificationCategory(identifier: category, actions: [], intentIdentifiers: [], options: [])
    }

    /// The request to open for a tapped push; dismissals and other payloads open nothing.
    static func requestID(userInfo: [AnyHashable: Any], actionIdentifier: String) -> String? {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = userInfo[requestIDKey] as? String else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
