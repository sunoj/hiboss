// Builds an immediate message cache value from current and snapshot APNs payloads.
// Exports: PushCachedMessage and PushMessageSnapshot.decode.
// Dependencies: Foundation JSON bridging and HibossKit message contracts.

import Foundation
import HibossKit

struct PushCachedMessage: Equatable, Sendable {
    let detail: MessageDetail
    let requiresRefresh: Bool
}

enum PushMessageSnapshot {
    static func decode(from userInfo: [AnyHashable: Any]) -> PushCachedMessage? {
        if let detail = decodeCompleteSnapshot(from: userInfo) {
            return PushCachedMessage(detail: detail, requiresRefresh: false)
        }
        guard let detail = decodeAlertPreview(from: userInfo) else { return nil }
        return PushCachedMessage(detail: detail, requiresRefresh: true)
    }

    private static func decodeCompleteSnapshot(from userInfo: [AnyHashable: Any]) -> MessageDetail? {
        guard let value = userInfo["message"], JSONSerialization.isValidJSONObject(value) else {
            return nil
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            let message = try JSONDecoder().decode(HistoryMessage.self, from: data)
            return MessageDetail(message: message, replies: [])
        } catch {
            return nil
        }
    }

    private static func decodeAlertPreview(from userInfo: [AnyHashable: Any]) -> MessageDetail? {
        guard
            let id = userInfo["messageId"] as? String,
            let direction = userInfo["direction"] as? String,
            let priority = userInfo["priority"] as? String,
            let aps = userInfo["aps"] as? [AnyHashable: Any],
            let alert = aps["alert"] as? [AnyHashable: Any],
            let body = alert["body"] as? String
        else { return nil }
        let agentName = userInfo["agentName"] as? String
        let title = alert["title"] as? String
        let options = userInfo["options"] as? [String] ?? []
        let metadata = MessageMetadata(options: options, content: alert["subtitle"] as? String)
        let message = HistoryMessage(
            id: MessageID(rawValue: id),
            body: body,
            agentName: agentName,
            direction: direction,
            status: "delivered",
            priority: priority,
            metadata: metadata,
            createdAt: Date().ISO8601Format(),
            sessionLabel: title == agentName || title == "HiBoss" ? nil : title
        )
        return MessageDetail(message: message, replies: [])
    }
}
