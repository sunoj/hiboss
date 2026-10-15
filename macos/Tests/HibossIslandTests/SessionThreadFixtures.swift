// Shared session conversation fixture for projection and full-window regressions.
// Exports: SessionThreadFixtures; timestamps are relative to the supplied clock.
// Dependencies: Foundation, HibossKit, and AttentionTestSupport.

import Foundation
import HibossKit

enum SessionThreadFixtures {
    static func history(now: Date = .now) -> [HistoryMessage] {
        func message(_ id: String, _ body: String, _ minutes: Double,
                     parent: String? = nil, boss: Bool = false,
                     metadata: MessageMetadata? = nil) -> HistoryMessage {
            HistoryMessage(id: MessageID(rawValue: id), body: body, agentName: "Build Agent",
                direction: boss ? "boss_to_agent" : "agent_to_boss",
                status: id == "answered" ? "replied" : "delivered", priority: "normal",
                replyTo: parent, metadata: metadata,
                expiresAt: id == "open" ? AttentionTestSupport.iso(now.addingTimeInterval(3600)) : nil,
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-minutes * 60)),
                sessionId: "thread-demo", sessionLabel: "Thread preview")
        }
        let reactions = MessageMetadata(options: [], reactions: [
            MessageReaction(emoji: "👍", actor: .boss, actorID: "one",
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-60))),
            MessageReaction(emoji: "👍", actor: .agent, actorID: "two",
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-50)))
        ])
        return [
            message("open", "Which validation should run next?", 4,
                metadata: MessageMetadata(options: ["Focused checks", "Full validation"],
                    defaultOption: "Focused checks")),
            message("answered", "The migration is ready. Continue with the review?", 30,
                metadata: MessageMetadata(options: ["Review", "Wait"])),
            message("reply", "Review", 25, parent: "answered", boss: true),
            message("follow", "Review complete. All focused checks passed.", 2,
                parent: "reply", metadata: reactions),
            message("update-1", "Indexed the changed files.", 20),
            message("update-2", "Validated the message models.", 15),
            message("update-3", "Prepared the review summary.", 10)
        ]
    }
}
