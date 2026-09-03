// Shared fixtures for attention ranking and island agreement tests.
// Exports: AttentionTestSupport ask/iso helpers.
// Dependencies: Foundation, HibossKit HistoryMessage.

import Foundation
import HibossKit
@testable import HibossIsland

enum AttentionTestSupport {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func ask(
        id: MessageID,
        body: String = "Needs a decision",
        priority: String = "normal",
        options: [String],
        defaultOption: String? = nil,
        isExpired: Bool = false,
        expiresAt: String? = nil,
        createdAt: String? = nil,
        status: String = "delivered",
        sessionLabel: String? = "proj/main",
        sessionBranch: String? = nil,
        sessionStatus: String? = nil,
        now: Date = AttentionTestSupport.now
    ) -> HistoryMessage {
        HistoryMessage(
            id: id,
            body: body,
            agentName: "Test Agent",
            direction: "agent_to_boss",
            status: status,
            priority: priority,
            metadata: MessageMetadata(
                options: options,
                isExpired: isExpired,
                defaultOption: defaultOption
            ),
            expiresAt: expiresAt,
            createdAt: createdAt ?? iso(now.addingTimeInterval(-60)),
            sessionId: id.rawValue,
            sessionLabel: sessionLabel,
            sessionBranch: sessionBranch,
            sessionStatus: sessionStatus
        )
    }
}
