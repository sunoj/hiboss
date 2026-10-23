// Silent "ask resolved" pushes: retract the ask's notifications and Live Activity on this phone.
// Exports: ResolutionNotice, ResolutionEffects, ResolutionPush (decode + handle) and
// DeliveredAskNotifications (which delivered notifications belong to closed asks).
// Dependencies: Foundation, PushPayloadCipher. Never logs ids' content, tokens or keys.

import Foundation

/// One ask that closed elsewhere: `status` is the server's `replied` or `expired`.
struct ResolutionNotice: Equatable, Sendable {
    let id: String
    let status: String
}

/// What a resolution does on this phone; the app uses `SystemResolutionEffects`.
@MainActor
protocol ResolutionEffects {
    func removeDeliveredNotifications(forAsk id: String) async
    func endActivity(forAsk id: String) async
    func markClosed(_ id: String)
}

enum ResolutionPush {
    /// Direct `hiboss.resolved` or relay `e` sealed for kind `resolved`; nil for anything else,
    /// including every decryption failure.
    static func decode(_ userInfo: [AnyHashable: Any], pushKey: Data?) -> ResolutionNotice? {
        if let hiboss = userInfo["hiboss"] as? [String: Any],
           let resolved = hiboss["resolved"] as? [String: Any] {
            return notice(from: resolved)
        }
        guard let encoded = userInfo["e"] as? String, let pushKey,
              let aps = userInfo["aps"] as? [String: Any], aps["alert"] == nil,
              let payload = try? PushPayloadCipher.open(encoded, pushKey: pushKey, kind: .resolved)
        else { return nil }
        return notice(from: payload)
    }

    private static func notice(from fields: [String: Any]) -> ResolutionNotice? {
        guard let id = fields["id"] as? String, !id.isEmpty,
              let status = fields["status"] as? String, status == "replied" || status == "expired"
        else { return nil }
        return ResolutionNotice(id: id, status: status)
    }

    /// Applies a decoded notice; returns false (and does nothing) when the payload is not one.
    @MainActor
    static func handle(_ notice: ResolutionNotice?, effects: any ResolutionEffects) async -> Bool {
        guard let notice else { return false }
        await effects.removeDeliveredNotifications(forAsk: notice.id)
        await effects.endActivity(forAsk: notice.id)
        effects.markClosed(notice.id)
        return true
    }
}

/// A delivered notification reduced to what reconciliation reads.
struct DeliveredNotificationRecord: Sendable {
    let identifier: String
    let date: Date
    let messageID: String?
    let category: String?
}

enum DeliveredAskNotifications {
    static let decisionCategory = "HIBOSS_OPTIONS"

    /// Notification identifiers for one ask, on both direct and relay paths.
    static func identifiers(in delivered: [DeliveredNotificationRecord], forAsk id: String) -> [String] {
        delivered.filter { $0.messageID == id }.map(\.identifier)
    }

    /// Notifications of asks that are no longer open: a decision alert, or a message history
    /// already records as closed. Only notifications delivered before the open list was read
    /// are judged, so a new ask whose push beat the list is never retracted.
    static func closedIdentifiers(
        in delivered: [DeliveredNotificationRecord], open: Set<String>, closed: Set<String>, readAt: Date
    ) -> [String] {
        delivered.filter { record in
            guard let id = record.messageID, !open.contains(id), record.date < readAt else { return false }
            return record.category == decisionCategory || closed.contains(id)
        }.map(\.identifier)
    }

    static func record(identifier: String, date: Date, userInfo: [AnyHashable: Any])
        -> DeliveredNotificationRecord
    {
        let aps = userInfo["aps"] as? [String: Any]
        return DeliveredNotificationRecord(
            identifier: identifier, date: date, messageID: userInfo["messageId"] as? String,
            category: userInfo["category"] as? String ?? aps?["category"] as? String
        )
    }
}
