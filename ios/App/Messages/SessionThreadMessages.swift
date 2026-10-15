// Joins loaded history with uncached live message events for the session conversation.
// Exports SessionThreadMessages; history remains authoritative for mutable message metadata.

import Foundation
import HibossKit

enum SessionThreadMessages {
    static func messages(sessionID: String, history: [HistoryMessage],
                         events: [SessionEvent]) -> [HistoryMessage] {
        var messages = MessageThread.fold(history).filter { thread in
            ([thread.message] + thread.entries).contains { SessionGrouping.sessionKey(for: $0) == sessionID }
        }.flatMap { [$0.message] + $0.entries }
        var loaded = Set(messages.map { $0.id.rawValue })
        for event in events where event.kind == "message" {
            let id = event.messageId ?? event.id
            guard loaded.insert(id).inserted else { continue }
            let payload = event.payload?.objectValue ?? [:]
            let metadata = payload["metadata"].flatMap { value in
                try? JSONDecoder().decode(MessageMetadata.self, from: JSONEncoder().encode(value))
            }
            messages.append(HistoryMessage(
                id: MessageID(rawValue: id), body: event.displayBody, agentName: event.actorName,
                direction: event.direction ?? "agent_to_boss", status: "delivered", priority: "normal",
                replyTo: payload["reply_to"]?.stringValue, metadata: metadata,
                createdAt: event.createdAt, sessionId: sessionID
            ))
        }
        return messages
    }
}
