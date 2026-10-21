// Turns a generic relay alert into the notification a direct APNs push would have shown.
// Exports: RelayNotificationContent.
// Dependencies: UserNotifications, PushPayloadCipher.

import Foundation
import UserNotifications

enum RelayNotificationContent {
    /// The rewritten content, or nil to keep the generic alert (not a relay push, no key,
    /// wrong key, swapped kind, truncated or oversized ciphertext, or unreadable plaintext).
    static func rewrite(_ content: UNNotificationContent, pushKey: Data?) -> UNMutableNotificationContent? {
        guard let pushKey,
              let encoded = content.userInfo["e"] as? String,
              let aps = content.userInfo["aps"] as? [String: Any],
              let alert = aps["alert"] as? [String: Any],
              let locKey = alert["loc-key"] as? String,
              let kind = PushKind(locKey: locKey),
              let payload = try? PushPayloadCipher.open(encoded, pushKey: pushKey, kind: kind),
              let directAPS = payload["aps"] as? [String: Any]
        else { return nil }
        guard let mutable = content.mutableCopy() as? UNMutableNotificationContent else { return nil }
        apply(alert: directAPS["alert"], to: mutable)
        mutable.categoryIdentifier = directAPS["category"] as? String ?? ""
        if let thread = directAPS["thread-id"] as? String { mutable.threadIdentifier = thread }
        mutable.userInfo = payload
        return mutable
    }

    private static func apply(alert: Any?, to content: UNMutableNotificationContent) {
        if let body = alert as? String {
            content.title = ""
            content.subtitle = ""
            content.body = body
            return
        }
        let fields = alert as? [String: Any] ?? [:]
        content.title = fields["title"] as? String ?? ""
        content.subtitle = fields["subtitle"] as? String ?? ""
        content.body = fields["body"] as? String ?? ""
    }
}
