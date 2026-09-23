// Attention-model tests for contract filtering, ranking, grouping, and expiry.
// Exports: HomeAttentionModelTests covering the Home root decision order.
// Dependencies: XCTest, HiBoss app target, HibossKit HistoryMessage.

import Foundation
import HibossKit
import XCTest
@testable import HiBoss

final class HomeAttentionModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testAllClearCompactsWhenPanelsExistAndStaysFullWithoutThem() {
        XCTAssertEqual(HomeAttentionLayout.allClearStyle(hasPanels: true), .compact)
        XCTAssertEqual(HomeAttentionLayout.allClearStyle(hasPanels: false), .full)
    }

    func testRanksAutoDecisionThenBlockedThenDeclaredPriority() {
        let messages = [
            message("priority", priority: "high", createdOffset: -500),
            message("blocked", priority: "low", sessionStatus: "waiting", createdOffset: -600),
            message("auto", priority: "low", expiresOffset: 120, defaultOption: "Hold", createdOffset: -30),
            message("normal", priority: "normal", expiresOffset: 180),
            message("low", priority: "low", sessionStatus: nil),
            message("expired-metadata", priority: "critical", isExpired: true),
        ]

        XCTAssertEqual(AttentionModel.items(from: messages, now: now).map(\.id), [
            "auto", "blocked", "priority", "normal", "low",
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

    func testBlockingTextAsksRemainActionableWithoutWaitingSessionOrPriority() {
        let ask = message("text", priority: "low", options: [], sessionStatus: "working")
        let timed = message("timed", expiresOffset: 30, options: [])
        let note = message("note", priority: "critical", options: [], mode: "async")
        let answered = message("answered", options: [], status: "replied")
        let expired = message("expired", options: [], isExpired: true)
        let outgoing = message("outgoing", options: [], direction: "boss_to_agent")

        XCTAssertEqual(Set(AttentionModel.items(from: [ask, timed, note, answered, expired, outgoing], now: now).map(\.id)),
                       Set(["text", "timed"]))
        XCTAssertTrue(AttentionModel.needsTextReply(ask, now: now))
        XCTAssertFalse(AttentionModel.needsTextReply(timed, now: now.addingTimeInterval(30)))
    }

    func testTextAsksDoNotChangeRelativeOptionDecisionOrder() {
        let decisions = [
            message("high", priority: "high"),
            message("blocked", sessionStatus: "waiting"),
            message("auto", expiresOffset: 30, defaultOption: "No")
        ]
        let mixed = decisions + [message("text", priority: "critical", options: [])]
        XCTAssertEqual(AttentionModel.items(from: mixed, now: now).filter { !$0.options.isEmpty }.map(\.id),
                       AttentionModel.items(from: decisions, now: now).map(\.id))
    }

    private func message(
        _ id: String,
        priority: String = "normal",
        expiresOffset: TimeInterval? = nil,
        defaultOption: String? = nil,
        options: [String] = ["Yes", "No"],
        mode: String = "blocking",
        status: String = "delivered",
        direction: String = "agent_to_boss",
        sessionStatus: String? = "working",
        sessionLabel: String? = "project",
        sessionBranch: String? = "main",
        content: String? = nil,
        isExpired: Bool = false,
        createdOffset: TimeInterval = -100
    ) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: id), body: "Question \(id)", agentName: "agent-\(id)",
            direction: direction, status: status, priority: priority,
            mode: mode, metadata: MessageMetadata(
                options: options, isExpired: isExpired,
                defaultOption: defaultOption, content: content
            ), expiresAt: expiresOffset.map { now.addingTimeInterval($0).ISO8601Format() },
            createdAt: now.addingTimeInterval(createdOffset).ISO8601Format(),
            sessionId: "session-\(id)", sessionLabel: sessionLabel, sessionBranch: sessionBranch,
            sessionStatus: sessionStatus
        )
    }
}
