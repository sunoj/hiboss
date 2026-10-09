// Ported iOS attention tests for identical filtering, ranking, grouping, and expiry.
// Exports: AttentionModelTests covering the shared decision order.
// Dependencies: XCTest and the public HibossKit attention API.

import Foundation
import HibossKit
import XCTest

final class AttentionModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

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
            message(
                "auto-high", priority: "high", expiresOffset: 60, defaultOption: "No", createdOffset: -20
            ),
            message(
                "auto-critical", priority: "critical", expiresOffset: 60,
                defaultOption: "Yes", createdOffset: -10
            ),
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

        let messages = [ask, timed, note, answered, expired, outgoing]
        XCTAssertEqual(Set(AttentionModel.items(from: messages, now: now).map(\.id)), Set(["text", "timed"]))
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

    func testOptionDecisionOrderAcrossDeadlineWaitingPriorityAndTimeout() {
        let messages = [
            message("priority", priority: "critical", createdOffset: -20),
            message("blocked", priority: "low", sessionStatus: "waiting", createdOffset: -40),
            message("auto", priority: "low", expiresOffset: 60, defaultOption: "No"),
            message("text", options: []),
            message("expired", isExpired: true),
        ]
        let options = AttentionModel.items(from: messages, now: now).filter { !$0.options.isEmpty }.map(\.id)
        XCTAssertEqual(options, ["auto", "blocked", "priority"])
        let later = now.addingTimeInterval(60)
        XCTAssertEqual(
            AttentionModel.items(from: messages, now: later).filter { !$0.options.isEmpty }.map(\.id),
            ["blocked", "priority"]
        )
    }

    func testWaitingSessionGroupsUnderWaitingOnYouAndBlockedSessionDoesNot() {
        let groups = AttentionModel.grouped(from: [
            message("waiting", sessionStatus: " Waiting "),
            message("blocked", sessionStatus: "blocked"),
        ], now: now)
        XCTAssertEqual(groups.map(\.group), [.waitingOnYou, .priority])
        XCTAssertEqual(groups.first?.items.map(\.id), ["waiting"])
    }

    func testEarlierAutoDeadlineBeatsPriorityAndOlderCreationBreaksPriorityTies() {
        let messages = [
            message("late", priority: "critical", expiresOffset: 100, defaultOption: "Yes"),
            message("early", priority: "low", expiresOffset: 10, defaultOption: "Yes"),
            message("newer", priority: "high", createdOffset: -20),
            message("older", priority: "high", createdOffset: -200),
        ]
        XCTAssertEqual(AttentionModel.items(from: messages, now: now).map(\.id), [
            "early", "late", "older", "newer",
        ])
    }

    func testWhitespaceDefaultAndWaitingDeadlineRemainInPriorityGroup() {
        let groups = AttentionModel.grouped(from: [
            message("blank", expiresOffset: 30, defaultOption: " \n "),
            message("timed-waiting", expiresOffset: 30, sessionStatus: "waiting"),
            message("no-deadline", defaultOption: "Yes"),
        ], now: now)
        XCTAssertEqual(groups.map(\.group), [.priority])
        XCTAssertEqual(groups.first?.items.count, 3)
    }

    func testResolvedExpiredOutgoingAndPeerOptionDecisionsNeverAppear() {
        let messages = [
            message("replied", status: "replied"),
            message("expired-status", status: "expired"),
            message("expired-metadata", isExpired: true),
            message("at-deadline", expiresOffset: 0),
            message("outgoing", direction: "boss_to_agent"),
            message("peer", direction: "agent_to_agent"),
        ]
        XCTAssertTrue(AttentionModel.items(from: messages, now: now).isEmpty)
        XCTAssertTrue(AttentionModel.grouped(from: messages, now: now).isEmpty)
    }

    func testPriorityCaseAndUnknownValuesMatchIOSRanksWithoutTrimming() {
        let items = AttentionModel.items(from: [
            message("low", priority: "LOW"),
            message("critical", priority: "CRITICAL"),
            message("unknown", priority: "unexpected", createdOffset: -300),
            message("spaced", priority: " high ", createdOffset: -200),
            message("normal", createdOffset: -100),
        ], now: now)
        XCTAssertEqual(items.map(\.id), ["critical", "unknown", "spaced", "normal", "low"])
        XCTAssertEqual(items.map { UrgencyKey($0).priority }, [3, 1, 1, 1, 0])
    }

    func testUrgencyKeyParsesSQLAndFractionalDatesAndSortsMalformedAgeLast() {
        let messages = [
            TodayTestSupport.message("sql", createdAt: "1970-01-12 13:46:40", options: ["Yes"]),
            TodayTestSupport.message("fractional", createdAt: "1970-01-12T13:46:40.500Z", options: ["Yes"]),
            TodayTestSupport.message("invalid", createdAt: "bad", options: ["Yes"]),
        ]
        let items = AttentionModel.items(from: Array(messages.reversed()), now: now)
        XCTAssertEqual(items.map(\.id), ["sql", "fractional", "invalid"])
        XCTAssertEqual(UrgencyKey(items[0]).created, now)
        XCTAssertEqual(UrgencyKey(items[1]).created, now.addingTimeInterval(0.5))
        XCTAssertEqual(UrgencyKey(items[2]).created, .distantFuture)
        XCTAssertLessThan(UrgencyKey(items[0]), UrgencyKey(items[1]))
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
