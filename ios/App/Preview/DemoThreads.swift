// Optional session conversation fixtures with follow-ups, reactions and merged updates.
// Exports DemoThreads; dates are captured once so refreshing does not reorder the fixture.

import Foundation
import HibossKit

enum DemoThreads {
    static let messages: [HistoryMessage] = makeMessages()
    static let pendingFollowup = message(
        "pending-followup", "I can keep the previous batch ready while you decide.",
        at: Date().addingTimeInterval(-20).ISO8601Format(), parent: "c5")

    static func appending(to history: [HistoryMessage]) -> [HistoryMessage] {
        let followup = history.contains { $0.id.rawValue == "c5" } ? [pendingFollowup] : []
        return history + messages + followup
    }

    private static func makeMessages() -> [HistoryMessage] {
        let now = Date()
        func date(_ seconds: TimeInterval) -> String { now.addingTimeInterval(seconds).ISO8601Format() }
        let reactions = [
            MessageReaction(emoji: "👍", actor: .boss, actorID: "demo-boss", createdAt: date(-15)),
            MessageReaction(emoji: "👍", actor: .agent, actorID: "demo-agent", createdAt: date(-10))
        ]
        return [
            message("thread-question", "Use the smaller release batch?", at: date(-900),
                    metadata: MessageMetadata(options: ["Small batch", "Full batch"]), status: "replied"),
            message("thread-reply", "Small batch", at: date(-800), parent: "thread-question",
                    direction: "boss_to_agent", metadata: MessageMetadata(options: [], source: "ios")),
            message("thread-followup", "The smaller batch is ready. All checks passed.", at: date(-30),
                    parent: "thread-reply", metadata: MessageMetadata(options: [], reactions: reactions)),
            message("update-first", "Release notes are ready.", at: date(-600)),
            message("update-second", "The staging checks are green too.", at: date(-500))
        ]
    }

    private static func message(_ id: String, _ body: String, at date: String, parent: String? = nil,
                                direction: String = "agent_to_boss", metadata: MessageMetadata? = nil,
                                status: String = "delivered") -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: id), body: body, agentName: "orchestrator-01",
                       direction: direction, status: status, priority: "normal", replyTo: parent,
                       metadata: metadata, createdAt: date, sessionId: "sess-deploy",
                       sessionLabel: "prod-release", sessionBranch: "release/v2.4")
    }
}
