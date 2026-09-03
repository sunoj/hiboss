// Unit tests for attention ranking bands, ties, grouping, and on-screen expiry.
// Covers: auto-decision, blocked, priority, and section grouping.
// Dependencies: XCTest, HibossKit fixtures, AttentionRanking.

import HibossKit
import XCTest
@testable import HibossIsland

final class AttentionRankingTests: XCTestCase {
    private let now = AttentionTestSupport.now
    private func iso(_ date: Date) -> String { AttentionTestSupport.iso(date) }
    private func ask(
        id: MessageID,
        priority: String = "normal",
        options: [String],
        defaultOption: String? = nil,
        isExpired: Bool = false,
        expiresAt: String? = nil,
        createdAt: String? = nil,
        sessionLabel: String? = "proj/main",
        sessionBranch: String? = nil,
        sessionStatus: String? = nil
    ) -> HistoryMessage {
        AttentionTestSupport.ask(
            id: id,
            priority: priority,
            options: options,
            defaultOption: defaultOption,
            isExpired: isExpired,
            expiresAt: expiresAt,
            createdAt: createdAt,
            sessionLabel: sessionLabel,
            sessionBranch: sessionBranch,
            sessionStatus: sessionStatus,
            now: now
        )
    }

    func testAutoDecisionOutranksBlockedAndDeclaredPriority() {
        let auto = ask(
            id: "auto",
            options: ["Ship", "Hold"],
            defaultOption: "Hold",
            expiresAt: iso(now.addingTimeInterval(90)),
            createdAt: iso(now.addingTimeInterval(-10)),
            sessionStatus: "waiting"
        )
        let blocked = ask(
            id: "blocked",
            priority: "critical",
            options: ["Approve"],
            createdAt: iso(now.addingTimeInterval(-3_600)),
            sessionStatus: "waiting"
        )
        let high = ask(
            id: "high",
            priority: "high",
            options: ["Look"],
            createdAt: iso(now.addingTimeInterval(-20)),
            sessionStatus: "working"
        )

        XCTAssertEqual(
            AttentionRanking.items(history: [high, blocked, auto], now: now).map(\.id.rawValue),
            ["auto", "blocked", "high"]
        )
    }

    func testBlockedWithoutDeadlineOutranksDeclaredPriority() {
        let blocked = ask(
            id: "blocked",
            options: ["Approve"],
            createdAt: iso(now.addingTimeInterval(-120)),
            sessionStatus: "waiting"
        )
        let critical = ask(
            id: "critical",
            priority: "critical",
            options: ["Ship"],
            createdAt: iso(now.addingTimeInterval(-10)),
            sessionStatus: "working"
        )

        XCTAssertEqual(
            AttentionRanking.items(history: [critical, blocked], now: now).map(\.id.rawValue),
            ["blocked", "critical"]
        )
    }

    func testCriticalOutranksHighWithinDeclaredPriority() {
        let high = ask(id: "high", priority: "high", options: ["A"], createdAt: iso(now.addingTimeInterval(-60)))
        let critical = ask(
            id: "critical",
            priority: "critical",
            options: ["B"],
            createdAt: iso(now.addingTimeInterval(-10))
        )

        XCTAssertEqual(
            AttentionRanking.items(history: [high, critical], now: now).map(\.id.rawValue),
            ["critical", "high"]
        )
    }

    func testNormalPriorityWithoutDeadlineOrWaitingIsExcluded() {
        let normal = ask(id: "normal", options: ["Ok"], sessionStatus: "working")
        let high = ask(id: "high", priority: "high", options: ["Look"], sessionStatus: "working")

        XCTAssertEqual(
            AttentionRanking.items(history: [normal, high], now: now).map(\.id.rawValue),
            ["high"]
        )
    }

    func testExpiredMetadataIsNeverAttention() {
        let expired = ask(
            id: "expired",
            options: ["Hold"],
            defaultOption: "Hold",
            isExpired: true,
            expiresAt: iso(now.addingTimeInterval(60)),
            sessionStatus: "waiting"
        )

        XCTAssertTrue(AttentionRanking.items(history: [expired], now: now).isEmpty)
    }

    func testItemExpiresWhileOnScreenLeavesAttention() {
        let message = ask(
            id: "ticking",
            options: ["Ship", "Hold"],
            defaultOption: "Hold",
            expiresAt: iso(now.addingTimeInterval(30)),
            createdAt: iso(now.addingTimeInterval(-5)),
            sessionStatus: "working"
        )

        let before = AttentionRanking.items(history: [message], now: now.addingTimeInterval(29))
        let after = AttentionRanking.items(history: [message], now: now.addingTimeInterval(31))

        XCTAssertEqual(before.map(\.id.rawValue), ["ticking"])
        XCTAssertEqual(before.first?.band(at: now.addingTimeInterval(29)), .autoDecision)
        XCTAssertTrue(after.isEmpty)
    }

    func testExpiredHighPriorityFallsToPriorityUntilMarkedExpired() {
        let message = ask(
            id: "was-auto",
            priority: "high",
            options: ["Ship"],
            defaultOption: "Ship",
            expiresAt: iso(now.addingTimeInterval(10)),
            createdAt: iso(now.addingTimeInterval(-20)),
            sessionStatus: "waiting"
        )

        XCTAssertEqual(
            AttentionRanking.items(history: [message], now: now).first?.band(at: now),
            .autoDecision
        )
        XCTAssertEqual(
            AttentionRanking.items(history: [message], now: now.addingTimeInterval(11))
                .first?.band(at: now.addingTimeInterval(11)),
            .declaredPriority
        )
    }

    func testSoonerExpiryWinsAutoDecisionTie() {
        let later = ask(
            id: "later",
            options: ["A"],
            defaultOption: "A",
            expiresAt: iso(now.addingTimeInterval(120)),
            createdAt: iso(now.addingTimeInterval(-100))
        )
        let sooner = ask(
            id: "sooner",
            options: ["B"],
            defaultOption: "B",
            expiresAt: iso(now.addingTimeInterval(60)),
            createdAt: iso(now.addingTimeInterval(-10))
        )

        XCTAssertEqual(
            AttentionRanking.items(history: [later, sooner], now: now).map(\.id.rawValue),
            ["sooner", "later"]
        )
    }

    func testOlderCreatedAtWinsWhenExpiryTied() {
        let newer = ask(
            id: "newer",
            options: ["A"],
            defaultOption: "A",
            expiresAt: iso(now.addingTimeInterval(60)),
            createdAt: iso(now.addingTimeInterval(-10))
        )
        let older = ask(
            id: "older",
            options: ["B"],
            defaultOption: "B",
            expiresAt: iso(now.addingTimeInterval(60)),
            createdAt: iso(now.addingTimeInterval(-100))
        )

        XCTAssertEqual(
            AttentionRanking.items(history: [newer, older], now: now).map(\.id.rawValue),
            ["older", "newer"]
        )
    }

    func testBlockedTieBreaksByLongestWaitThenId() {
        let newer = ask(
            id: "b-newer",
            options: ["A"],
            createdAt: iso(now.addingTimeInterval(-10)),
            sessionStatus: "waiting"
        )
        let older = ask(
            id: "b-older",
            options: ["B"],
            createdAt: iso(now.addingTimeInterval(-100)),
            sessionStatus: "waiting"
        )

        XCTAssertEqual(
            AttentionRanking.items(history: [newer, older], now: now).map(\.id.rawValue),
            ["b-older", "b-newer"]
        )
    }

    func testGroupingSkipsEmptyBandsAndPreservesOrder() {
        let auto = ask(
            id: "auto",
            options: ["Hold"],
            defaultOption: "Hold",
            expiresAt: iso(now.addingTimeInterval(40))
        )
        let high = ask(id: "high", priority: "high", options: ["Look"])
        let items = AttentionRanking.items(history: [high, auto], now: now)
        let sections = AttentionRanking.grouped(items, now: now)

        XCTAssertEqual(sections.map(\.band), [.autoDecision, .declaredPriority])
        XCTAssertEqual(sections[0].items.map(\.id.rawValue), ["auto"])
        XCTAssertEqual(sections[1].items.map(\.id.rawValue), ["high"])
    }

    func testProjectFallsBackFromLabelToBranch() {
        let labeled = AttentionItem(message: ask(
            id: "labeled",
            priority: "high",
            options: ["A"],
            sessionLabel: "payments/hotfix",
            sessionBranch: "feat/ignored"
        ))
        let branched = AttentionItem(message: ask(
            id: "branched",
            priority: "high",
            options: ["B"],
            sessionLabel: nil,
            sessionBranch: "feat/session"
        ))

        XCTAssertEqual(labeled.project, "payments/hotfix")
        XCTAssertEqual(branched.project, "feat/session")
    }
}
