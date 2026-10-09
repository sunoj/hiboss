// Tests Today decisions, input merging, delivered eligibility, and truthful all-clear.
// Exports: TodaySnapshotTests exercising the public pure projection.
// Dependencies: XCTest, HibossKit, and TodayTestSupport fixtures.

import XCTest
import HibossKit

final class TodaySnapshotTests: XCTestCase {
    private let now = TodayTestSupport.now

    func testDecisionsUseSharedRankingAndIncludeRequiredInputsOnce() {
        let history = [
            TodayTestSupport.message("priority", options: ["Yes"], priority: "high"),
            TodayTestSupport.message("waiting", options: ["Yes"], sessionStatus: "waiting"),
            TodayTestSupport.message("auto", options: ["Old"], priority: "low"),
        ]
        let required = [
            TodayTestSupport.message("auto", options: ["New"], expiresIn: 30, defaultOption: "New"),
            TodayTestSupport.message("text", options: [], mode: "blocking"),
        ]
        let snapshot = TodayTestSupport.snapshot(history, requiredInputs: required)
        XCTAssertEqual(snapshot.decisions.map(\.id), ["auto", "text", "waiting", "priority"])
        XCTAssertEqual(snapshot.decisions.first?.options, ["New"])
        XCTAssertEqual(snapshot.decisions, AttentionModel.items(
            from: [history[0], history[1]] + required, now: now
        ))
        XCTAssertFalse(snapshot.isAllClear)
    }

    func testWithdrawnIDsAreAbsentFromDecisionsAndResultsButKeepSessionEvidence() {
        let snapshot = TodayTestSupport.snapshot([
            TodayTestSupport.message("decision", session: "asks", options: ["Yes"]),
            TodayTestSupport.message("result", session: "results"),
        ], withdrawn: ["decision", "result"])
        XCTAssertTrue(snapshot.decisions.isEmpty)
        XCTAssertTrue(snapshot.delivered.isEmpty)
        XCTAssertTrue(snapshot.sessionDirectory.needsYou.isEmpty)
        XCTAssertEqual(Set(snapshot.working.map(\.id)), Set(["asks", "results"]))
        XCTAssertTrue(snapshot.isAllClear)
    }

    func testLastDuplicateWinsWithinHistoryAndRequiredInputs() {
        let snapshot = TodayTestSupport.snapshot([
            TodayTestSupport.message("same", options: ["History first"]),
            TodayTestSupport.message("same", options: ["History last"]),
        ], requiredInputs: [
            TodayTestSupport.message("same", options: ["Required first"]),
            TodayTestSupport.message("same", options: ["Required last"]),
        ])
        XCTAssertEqual(snapshot.decisions.count, 1)
        XCTAssertEqual(snapshot.decisions.first?.options, ["Required last"])
        XCTAssertEqual(snapshot.working.count, 1)
    }

    func testDeliveredContainsOnlyNonblockingAgentResultsOutsideOpenDecisions() {
        let snapshot = TodayTestSupport.snapshot([
            TodayTestSupport.message("note", age: 1),
            TodayTestSupport.message("reply", age: 2, options: ["Yes"], status: "replied"),
            TodayTestSupport.message("expired", age: 3, options: ["Yes"], status: "expired"),
            TodayTestSupport.message("open", age: 4, options: ["Yes"]),
            TodayTestSupport.message("blocking-note", age: 5, mode: "blocking"),
            TodayTestSupport.message(
                "blocking-replied", options: ["Yes"], mode: "blocking", status: "replied"
            ),
            TodayTestSupport.message("outgoing", direction: "boss_to_agent"),
            TodayTestSupport.message("peer", direction: "agent_to_agent"),
            TodayTestSupport.message("elapsed-options", options: ["Yes"], expiresIn: -1),
        ])
        XCTAssertEqual(snapshot.delivered.map(\.id), ["note", "reply", "expired"])
        XCTAssertEqual(Set(snapshot.decisions.map(\.id)), Set(["open", "blocking-note"]))
    }

    func testDeliveredWindowIncludesBoundaryAndRejectsOldFutureAndMalformedDates() {
        let window = TodaySnapshot.deliveredWindow
        let snapshot = TodayTestSupport.snapshot([
            TodayTestSupport.message("now", age: 0),
            TodayTestSupport.message("boundary", age: window),
            TodayTestSupport.message("old", age: window + 1),
            TodayTestSupport.message("future", age: -1),
            TodayTestSupport.message("malformed", createdAt: "not-a-date"),
        ])
        XCTAssertEqual(window, 86_400)
        XCTAssertEqual(snapshot.delivered.map(\.id), ["now", "boundary"])
    }

    func testDeliveredSortsNewestFirstWithStableIDTiesAndCapsAtTwenty() {
        let results = (0..<25).map { index in
            TodayTestSupport.message(String(format: "result-%02d", index), age: TimeInterval(index))
        }
        let snapshot = TodayTestSupport.snapshot(Array(results.reversed()))
        XCTAssertEqual(TodaySnapshot.deliveredLimit, 20)
        XCTAssertEqual(snapshot.delivered.map(\.id), Array(results.prefix(20)).map(\.id))
        let tied = [TodayTestSupport.message("b"), TodayTestSupport.message("a")]
        XCTAssertEqual(TodayTestSupport.snapshot(tied).delivered.map(\.id), ["a", "b"])
    }

    func testAllClearRequiresNoDecisionsLiveHealthAndCompleteCoverage() {
        let states: [TodayHealth] = [
            .live(checkedAt: now), .connecting, .offline(since: now.addingTimeInterval(-100)), .loading,
        ]
        for health in states {
            for covered in [false, true] {
                for hasDecision in [false, true] {
                    let messages = hasDecision ? [TodayTestSupport.message("ask", options: ["Yes"])] : []
                    let snapshot = TodayTestSupport.snapshot(
                        messages, health: health, coverageComplete: covered
                    )
                    XCTAssertEqual(snapshot.health, health)
                    XCTAssertEqual(snapshot.coverageComplete, covered)
                    XCTAssertEqual(snapshot.isAllClear, health == states[0] && covered && !hasDecision)
                }
            }
        }
    }

    func testInjectedNowAloneChangesExpiryAndRecencyAndSnapshotsAreValues() {
        let history = [TodayTestSupport.message("ask", options: ["Yes"], expiresIn: 30)]
        let first = TodayTestSupport.snapshot(history)
        XCTAssertEqual(first, TodayTestSupport.snapshot(history))
        let later = TodayTestSupport.snapshot(history, now: now.addingTimeInterval(30))
        XCTAssertTrue(later.decisions.isEmpty)
        XCTAssertTrue(later.isAllClear)
        XCTAssertNotEqual(first, later)
        assertSendable(first)
        assertSendable(first.sessionDirectory)
        assertSendable(first.working[0])
        assertSendable(first.decisions[0])
        assertSendable(UrgencyKey(first.decisions[0]))
    }

    private func assertSendable<T: Sendable>(_ value: T) {}
}
