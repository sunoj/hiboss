// Unit tests for attention ranking bands, ties, grouping, and on-screen expiry.
// Covers: auto-decision, blocked, priority, and section grouping.
// Dependencies: XCTest, HibossKit fixtures, TodayProjection.

import HibossKit
import XCTest
@testable import HibossIsland

final class TodayProjectionTests: XCTestCase {
    private let now = AttentionTestSupport.now
    private func iso(_ date: Date) -> String { AttentionTestSupport.iso(date) }
    private func decisions(requiredInputs: [HistoryMessage], now: Date) -> [AttentionItem] {
        TodaySnapshot(history: [], requiredInputs: requiredInputs, health: .live(checkedAt: now),
            coverageComplete: true, now: now).decisions
    }

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
            decisions(requiredInputs: [high, blocked, auto], now: now).map(\.id.rawValue),
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
            decisions(requiredInputs: [critical, blocked], now: now).map(\.id.rawValue),
            ["blocked", "critical"]
        )
    }

    func testCriticalOutranksHighWithinDeclaredPriority() {
        let high = ask(id: "high", priority: "high", options: ["A"],
            createdAt: iso(now.addingTimeInterval(-60)))
        let critical = ask(
            id: "critical",
            priority: "critical",
            options: ["B"],
            createdAt: iso(now.addingTimeInterval(-10))
        )

        XCTAssertEqual(
            decisions(requiredInputs: [high, critical], now: now).map(\.id.rawValue),
            ["critical", "high"]
        )
    }

    func testOrdinaryQuestionFollowsDeclaredPriority() {
        let normal = ask(id: "normal", options: ["Ok"], sessionStatus: "working")
        let high = ask(id: "high", priority: "high", options: ["Look"], sessionStatus: "working")

        XCTAssertEqual(
            decisions(requiredInputs: [normal, high], now: now).map(\.id.rawValue),
            ["high", "normal"]
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

        XCTAssertTrue(decisions(requiredInputs: [expired], now: now).isEmpty)
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

        let before = decisions(requiredInputs: [message], now: now.addingTimeInterval(29))
        let after = decisions(requiredInputs: [message], now: now.addingTimeInterval(31))

        XCTAssertEqual(before.map(\.id.rawValue), ["ticking"])
        XCTAssertEqual(before.first?.group, .autoDecision)
        XCTAssertTrue(after.isEmpty)
    }

    func testExpiredHighPriorityLeavesAttentionAtDeadline() {
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
            decisions(requiredInputs: [message], now: now).first?.group,
            .autoDecision
        )
        XCTAssertEqual(
            decisions(requiredInputs: [message], now: now.addingTimeInterval(11))
                .first?.group,
            nil
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
            decisions(requiredInputs: [later, sooner], now: now).map(\.id.rawValue),
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
            decisions(requiredInputs: [newer, older], now: now).map(\.id.rawValue),
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
            decisions(requiredInputs: [newer, older], now: now).map(\.id.rawValue),
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
        let items = decisions(requiredInputs: [high, auto], now: now)
        let sections = AttentionModel.grouped(from: items.map(\.message), now: now)

        XCTAssertEqual(sections.map(\.group), [.autoDecision, .priority])
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
        ), group: .priority)
        let branched = AttentionItem(message: ask(
            id: "branched",
            priority: "high",
            options: ["B"],
            sessionLabel: nil,
            sessionBranch: "feat/session"
        ), group: .priority)

        XCTAssertEqual(labeled.projectTitle, "payments/hotfix")
        XCTAssertEqual(branched.projectTitle, "feat/session")
    }
}
