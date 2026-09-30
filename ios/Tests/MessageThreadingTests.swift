// Messages list model tests: boss replies fold into their parent, orphans stay the boss's own.
// Exports: MessageThreadingTests covering MessageThreading and MessageRowBadge.
// Dependencies: XCTest, HiBoss app target, HibossKit.

import HibossKit
import XCTest
@testable import HiBoss

final class MessageThreadingTests: XCTestCase {
    func testReplyFoldsIntoParentAndEmitsNoRow() {
        let items = MessageThreading.items(from: [Self.ask, Self.reply("r1", to: "q1", body: "Ship")])
        XCTAssertEqual(items.map(\.id.rawValue), ["q1"])
        guard case let .agent(message, reply) = items[0] else { return XCTFail("expected agent row") }
        XCTAssertEqual(message.id.rawValue, "q1")
        XCTAssertEqual(reply?.body, "Ship")
    }

    func testReplyCarryingAgentNameIsStillBossAuthored() {
        let orphan = Self.reply("r9", to: "missing", body: "Hold")
        let items = MessageThreading.items(from: [orphan])
        XCTAssertEqual(items, [.boss(orphan)])
        XCTAssertEqual(orphan.agentName, "orchestrator-01")
    }

    func testBossMessageWithoutReplyToIsOwnRow() {
        let steer = Self.reply("s1", to: nil, body: "Pause the rollout")
        XCTAssertEqual(MessageThreading.items(from: [steer, Self.ask]).map(\.id.rawValue), ["s1", "q1"])
        XCTAssertEqual(MessageThreading.items(from: [steer]), [.boss(steer)])
    }

    func testNewestOfSeveralRepliesWins() {
        let early = Self.reply("r1", to: "q1", body: "Hold", at: "2026-08-14T10:01:00Z")
        let late = Self.reply("r2", to: "q1", body: "Ship", at: "2026-08-14T10:05:00Z")
        let items = MessageThreading.items(from: [late, Self.ask, early])
        XCTAssertEqual(items, [.agent(Self.ask, reply: late)])
    }

    func testAgentOrderIsPreservedAndUnansweredHaveNoReply() {
        let update = Self.message("u1", direction: "agent_to_boss", priority: "normal")
        let items = MessageThreading.items(from: [update, Self.ask])
        XCTAssertEqual(items, [.agent(update, reply: nil), .agent(Self.ask, reply: nil)])
    }

    func testAutoDecidedAnswerIsNotAttributedToBoss() {
        let auto = HistoryMessage(
            id: "x", body: "Run it?", agentName: "worker", direction: "agent_to_boss",
            status: "replied", priority: "normal",
            metadata: MessageMetadata(options: ["Run", "Skip"], isExpired: true),
            createdAt: "2026-08-14T10:00:00Z"
        )
        XCTAssertNil(MessageThreading.bossAnswer(for: auto, answer: "Skip"))
        XCTAssertEqual(MessageRowBadge.badge(for: auto), .autoDecided)
        XCTAssertEqual(MessageThreading.bossAnswer(for: Self.ask, answer: " Ship "), "Ship")
        XCTAssertNil(MessageThreading.bossAnswer(for: Self.ask, answer: "  "))
    }

    func testBadgePrecedence() {
        XCTAssertEqual(MessageRowBadge.badge(for: Self.ask), .decisionNeeded)
        let answered = Self.message("a", direction: "agent_to_boss", priority: "critical", status: "replied")
        XCTAssertEqual(MessageRowBadge.badge(for: answered), .critical)
        let expired = Self.message("e", direction: "agent_to_boss", priority: "high", status: "expired")
        XCTAssertEqual(MessageRowBadge.badge(for: expired), .expired)
        XCTAssertEqual(MessageRowBadge.badge(for: Self.message("h", direction: "agent_to_boss", priority: "high")), .high)
        XCTAssertNil(MessageRowBadge.badge(for: Self.message("n", direction: "agent_to_boss", priority: "normal")))
    }

    private static let ask = HistoryMessage(
        id: "q1", body: "Ship the changelog?", agentName: "orchestrator-01",
        direction: "agent_to_boss", status: "delivered", priority: "high",
        mode: "blocking", type: "approval_request",
        metadata: MessageMetadata(options: ["Ship", "Hold"]),
        createdAt: "2026-08-14T10:00:00Z"
    )

    private static func reply(_ id: String, to parent: String?, body: String,
                              at date: String = "2026-08-14T10:02:00Z") -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: id), body: body, agentName: "orchestrator-01",
            direction: "boss_to_agent", status: "sent", priority: "normal",
            replyTo: parent, createdAt: date
        )
    }

    private static func message(_ id: String, direction: String, priority: String,
                                status: String = "delivered") -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: id), body: "b", agentName: "worker",
            direction: direction, status: status, priority: priority,
            createdAt: "2026-08-14T10:00:00Z"
        )
    }
}
