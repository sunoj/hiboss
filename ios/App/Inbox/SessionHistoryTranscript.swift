// Projects cached boss history into the same message rows as the live session transcript.
// Exports SessionHistoryTranscript; session membership follows SessionGrouping exactly.
// Dependencies: HibossKit HistoryMessage, SessionEvent, and chronological message dates.

import HibossKit
import Foundation

enum SessionHistoryTranscript {
    static func events(sessionID: String, messages: [HistoryMessage]) -> [SessionEvent] {
        messages.enumerated()
            .filter { SessionGrouping.sessionKey(for: $0.element) == sessionID }
            .sorted {
                let left = $0.element.createdDate ?? .distantPast
                let right = $1.element.createdDate ?? .distantPast
                return left == right ? $0.offset < $1.offset : left < right
            }
            .enumerated()
            .map { index, entry in
                let message = entry.element
                return SessionEvent(
                    id: "history-\(message.id.rawValue)", sessionId: sessionID, sequence: index + 1,
                    kind: "message", direction: message.direction, actorName: message.agentName,
                    messageId: message.id.rawValue,
                    payload: .object([
                        "body": .string(message.body),
                        "metadata": .object(["auto_default": .bool(message.metadata?.isAutoDefault == true)]),
                    ]),
                    createdAt: message.createdAt
                )
            }
    }
}
