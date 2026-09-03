// Attention-model tests for contract filtering, ranking, grouping, and expiry.
// Exports: HomeAttentionModelTests covering the Home root decision order.
// Dependencies: XCTest, HiBoss app target, HibossKit HistoryMessage.

import Foundation
import HibossKit
import XCTest
@testable import HiBoss

final class HomeAttentionModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testRanksAutoDecisionThenBlockedThenDeclaredPriority() {
        let messages = [
            message("priority", priority: "high", createdOffset: -500),
            message("blocked", priority: "low", sessionStatus: "waiting", createdOffset: -600),
            message("auto", priority: "low", expiresOffset: 120, defaultOption: "Hold", createdOffset: -30),
            message("normal", priority: "normal"),
            message("expired-metadata", priority: "critical", isExpired: true),
        ]

        XCTAssertEqual(AttentionModel.items(from: messages, now: now).map(\.id), [
            "auto", "blocked", "priority",
        ])
    }

    func testTieBreaksByDeadlinePriorityAgeAndId() {
        let messages = [
            message("auto-high", priority: "high", expiresOffset: 60, defaultOption: "No", createdOffset: -20),
            message("auto-critical", priority: "critical", expiresOffset: 60, defaultOption: "Yes", createdOffset: -10),
            message("blocked-b", priority: "high", sessionStatus: "waiting", createdOffset: -20),
            message("blocked-a", priority: "high", sessionStatus: "waiting", createdOffset: -20),
        ]

        XCTAssertEqual(AttentionModel.items(from: messages, now: now).map(\.id), [
            "auto-critical", "auto-high", "blocked-a", "blocked-b",
        ])
    }

    func testDeadlineCrossingRemovesItemAndExpiredMetadataNeverAppears() {
        let deadline = message("deadline", expiresOffset: 1, defaultOption: "Ship")
        let expired = message("already-decided", priority: "critical", isExpired: true)

        XCTAssertEqual(AttentionModel.items(from: [deadline, expired], now: now).map(\.id), ["deadline"])
        XCTAssertTrue(AttentionModel.items(from: [deadline], now: now.addingTimeInterval(2)).isEmpty)
    }

    func testAttentionItemCarriesProjectFallbackAndMessageContext() {
        let item = AttentionModel.items(from: [
            message(
                "context", priority: "high", sessionLabel: " ", sessionBranch: "feature/branch",
                content: "Additional context"
            ),
        ], now: now).first

        XCTAssertEqual(item?.project, "feature/branch")
        XCTAssertEqual(item?.message.agentName, "agent-context")
        XCTAssertEqual(item?.message.content, "Additional context")
        XCTAssertEqual(item?.options, ["Yes", "No"])
    }

    private func message(
        _ id: String,
        priority: String = "normal",
        expiresOffset: TimeInterval? = nil,
        defaultOption: String? = nil,
        sessionStatus: String? = "working",
        sessionLabel: String? = "project",
        sessionBranch: String? = "main",
        content: String? = nil,
        isExpired: Bool = false,
        createdOffset: TimeInterval = -100
    ) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: id), body: "Question \(id)", agentName: "agent-\(id)",
            direction: "agent_to_boss", status: "delivered", priority: priority,
            mode: "blocking", metadata: MessageMetadata(
                options: ["Yes", "No"], isExpired: isExpired,
                defaultOption: defaultOption, content: content
            ), expiresAt: expiresOffset.map { now.addingTimeInterval($0).ISO8601Format() },
            createdAt: now.addingTimeInterval(createdOffset).ISO8601Format(),
            sessionId: "session-\(id)", sessionLabel: sessionLabel, sessionBranch: sessionBranch,
            sessionStatus: sessionStatus
        )
    }
}
