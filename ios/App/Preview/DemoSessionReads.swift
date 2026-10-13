// Deterministic attention, unread, working and idle sessions for read-state verification.
// Exports DemoSessionReads fixtures and a baseline preceding only the new agent messages.
// Dependencies: Foundation and HibossKit history models; enabled only in demo mode.

import Foundation
import HibossKit

enum DemoSessionReads {
    static let baseline = Date().addingTimeInterval(-7_200)

    static var messages: [HistoryMessage] {
        [message("needs", body: "Choose the release window", offset: -60, options: ["Morning", "Evening"]),
         message("working", body: "Running the release checks", offset: -120),
         message("unread", body: "The accessibility review is ready", offset: -3_600),
         message("idle", body: "Documentation is complete", offset: -10_000),
         message("idle", body: "Thanks for the update", offset: -9_000, direction: "boss_to_agent")]
    }

    private static func message(_ session: String, body: String, offset: TimeInterval,
                                direction: String = "agent_to_boss", options: [String] = []) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: "read-\(session)-\(direction)"), body: body, agentName: "Release agent",
            direction: direction, status: "delivered", priority: "normal",
            mode: options.isEmpty ? "async" : "blocking", metadata: MessageMetadata(options: options),
            createdAt: Date().addingTimeInterval(offset).ISO8601Format(), sessionId: "read-\(session)",
            sessionLabel: session == "unread" ? "Review" : session.capitalized, sessionStatus: session == "working" ? "working" : "idle"
        )
    }
}
