// Targeted message lookup for demo-mode notification deep links.
// Exports: targeted fetches and current-production notification preview payloads.
// Dependencies: Foundation process environment, DemoBossAPI, and HibossKit.

import Foundation
import HibossKit

extension DemoBossAPI {
    func messageDetail(for messageID: MessageID) -> MessageDetail? {
        guard let message = messages.first(where: { $0.id == messageID }) else { return nil }
        let replies = messages.filter { $0.replyTo == messageID.rawValue }
        return MessageDetail(message: message, replies: replies)
    }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        let rawDelay = ProcessInfo.processInfo.environment["HIBOSS_DEMO_MESSAGE_DELAY_MS"] ?? "0"
        let delay = UInt64(rawDelay) ?? 0
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        guard let detail = messageDetail(for: messageID) else {
            throw HibossAPIError.requestFailed(status: 404, message: "")
        }
        return detail
    }

    func notificationPreviewUserInfo(for messageID: MessageID) -> [AnyHashable: Any]? {
        guard let message = messageDetail(for: messageID)?.message else { return nil }
        var alert: [AnyHashable: Any] = [
            "title": message.sessionLabel ?? message.agentName ?? "HiBoss",
            "body": message.body,
        ]
        if let content = message.metadata?.content { alert["subtitle"] = content }
        return [
            "aps": ["alert": alert],
            "messageId": message.id.rawValue,
            "agentName": message.agentName ?? "HiBoss",
            "priority": message.priority,
            "direction": message.direction,
            "options": message.options,
        ]
    }
}
