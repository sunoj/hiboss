// Tests session provenance, recency, exhaustive buckets, and agreement with Today.
// Exports: SessionDirectoryTests covering shared live-work and decision membership.
// Dependencies: XCTest, HibossKit, and TodayTestSupport fixtures.

import XCTest
import HibossKit

final class SessionDirectoryTests: XCTestCase {
    private let now = TodayTestSupport.now

    /// A "working" status is not "working now" once its last message is older than two hours.
    func testWorkingExcludesStaleWorkingStatusAndListsRecentActivityOncePerSessionNewestFirst() {
        let history = [
            TodayTestSupport.message("old-working", session: "old", age: 10_000, sessionStatus: " Working "),
            TodayTestSupport.message("first", session: "recent", age: 200),
            TodayTestSupport.message("last", session: "recent", age: 10, direction: "boss_to_agent"),
            TodayTestSupport.message("waiting", session: "waiting", age: 20, sessionStatus: "waiting"),
            TodayTestSupport.message("idle", session: "idle", age: 10_000),
        ]
        let snapshot = TodayTestSupport.snapshot(history)
        XCTAssertEqual(snapshot.working.map(\.id), ["recent", "waiting"])
        XCTAssertEqual(snapshot.working.map(\.needsYou), [false, false])
        XCTAssertEqual(snapshot.working.first?.lastActivityDate, now.addingTimeInterval(-10))
    }

    func testActivityWindowIsInclusiveAndRejectsFutureAndUnknownDates() {
        let window = TodaySession.activityWindow
        let history = [
            TodayTestSupport.message("boundary", session: "boundary", age: window),
            TodayTestSupport.message("old", session: "old", age: window + 1),
            TodayTestSupport.message("future", session: "future", age: -1),
            TodayTestSupport.message("bad", session: "bad", createdAt: "bad"),
            TodayTestSupport.message(
                "bad-working", session: "bad-working", createdAt: "bad", sessionStatus: "working"
            ),
        ]
        let snapshot = TodayTestSupport.snapshot(history)
        XCTAssertEqual(window, 900)
        // An unknown date cannot establish activity, even with a "working" status.
        XCTAssertEqual(snapshot.working.map(\.id), ["boundary"])
        XCTAssertEqual(snapshot.sessionDirectory.idle.map(\.id), ["future", "old", "bad", "bad-working"])
        XCTAssertFalse(snapshot.working[0].hasLiveWork(now: now.addingTimeInterval(1)))
    }

    func testNewestStatusAndProvenanceWinIndependentlyOfInputOrder() {
        let older = TodayTestSupport.message(
            "older", age: 10_000, sessionStatus: "working",
            label: "Old", branch: "old", agent: "Old agent"
        )
        let newer = TodayTestSupport.message(
            "newer", age: 9_000, sessionStatus: "completed",
            label: "New", branch: "feature", agent: "New agent"
        )
        let snapshot = TodayTestSupport.snapshot([newer, older])
        XCTAssertTrue(snapshot.working.isEmpty)
        let session = snapshot.sessionDirectory.idle.first
        XCTAssertEqual(session?.projectLabel, "New")
        XCTAssertEqual(session?.branch, "feature")
        XCTAssertEqual(session?.agentName, "New agent")
        XCTAssertEqual(session?.status, "completed")
        XCTAssertEqual(session?.statusText, "Body newer")
        XCTAssertEqual(session?.lastActivityDate, now.addingTimeInterval(-9_000))
        XCTAssertEqual(snapshot, TodayTestSupport.snapshot([older, newer]))
    }

    func testMissingLatestProvenanceFallsBackToPreviousNonemptyValues() {
        let history = [
            TodayTestSupport.message("old", age: 300, sessionStatus: "working"),
            TodayTestSupport.message("new", age: 10, sessionStatus: " ", label: " ", branch: nil, agent: nil),
        ]
        let session = TodayTestSupport.snapshot(history).working.first
        XCTAssertEqual(session?.projectLabel, "Project")
        XCTAssertEqual(session?.branch, "main")
        XCTAssertEqual(session?.agentName, "Agent")
        XCTAssertEqual(session?.status, "working")
        XCTAssertEqual(session?.statusText, "Body new")
    }

    func testMixedTimestampFormatsAndRequiredOverridesPreserveSessionProvenance() {
        let history = [
            TodayTestSupport.message("invalid", createdAt: "invalid", label: "Invalid"),
            TodayTestSupport.message("tie-b", createdAt: "1970-01-12T13:45:00Z", label: "Second"),
            TodayTestSupport.message("tie-a", createdAt: "1970-01-12 13:45:00", label: "First"),
            TodayTestSupport.message("newest", createdAt: "1970-01-12T13:46:20.000Z",
                sessionStatus: nil, label: nil, branch: nil, agent: nil),
        ]
        let before = TodayTestSupport.snapshot(history).working.first
        XCTAssertEqual(before?.projectLabel, "First")
        XCTAssertEqual(before?.statusText, "Body newest")
        XCTAssertEqual(before?.lastActivityDate, now.addingTimeInterval(-20))
        let replacement = TodayTestSupport.message("tie-b", createdAt: "1970-01-12 13:46:30",
            label: "Required", branch: nil, agent: nil)
        let snapshot = TodayTestSupport.snapshot(history, requiredInputs: [replacement])
        let session = snapshot.working.first
        XCTAssertEqual(session?.projectLabel, "Required")
        XCTAssertEqual(session?.statusText, "Body tie-b")
        XCTAssertEqual(session?.branch, "main")
        XCTAssertEqual(session?.agentName, "Agent")
        XCTAssertEqual(session?.lastActivityDate, now.addingTimeInterval(-10))
        XCTAssertEqual(snapshot.sessionDirectory, SessionDirectory(
            history: Array(history.reversed()), requiredInputs: [replacement], now: now))
    }

    func testNeedsYouTakesDirectoryPrecedenceWhileTodayWorkingKeepsNeedsYouFlag() {
        let history = [
            TodayTestSupport.message(
                "live-ask", session: "live-ask", options: ["Yes"], sessionStatus: "working"
            ),
            TodayTestSupport.message("old-ask", session: "old-ask", age: 10_000, mode: "blocking"),
            TodayTestSupport.message("work", session: "work"),
            TodayTestSupport.message("idle", session: "idle", age: 10_000),
        ]
        // The two asks are on the server's open list; history alone never opens a decision.
        let snapshot = TodayTestSupport.snapshot(history, requiredInputs: Array(history.prefix(2)))
        let directory = snapshot.sessionDirectory
        XCTAssertEqual(directory.needsYou.map(\.id), ["live-ask", "old-ask"])
        XCTAssertEqual(directory.working.map(\.id), ["work"])
        XCTAssertEqual(directory.idle.map(\.id), ["idle"])
        XCTAssertEqual(snapshot.working.map(\.id), ["live-ask", "work"])
        XCTAssertEqual(snapshot.working.map(\.needsYou), [true, false])
        let all = directory.needsYou + directory.working + directory.idle
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(Set(all.map(\.id)).count, 4)
        XCTAssertEqual(directory, SessionDirectory(history: history, requiredInputs: Array(history.prefix(2)), now: now))
    }

    func testExpiryResolutionAndWithdrawalRemoveNeedsYouUsingSharedRules() {
        let history = [
            TodayTestSupport.message("expired", session: "expired", options: ["Yes"], expiresIn: 0),
            TodayTestSupport.message("resolved", session: "resolved", options: ["Yes"], status: "replied"),
            TodayTestSupport.message("withdrawn", session: "withdrawn", options: ["Yes"]),
        ]
        let required = [
            TodayTestSupport.message("required", session: "required", age: 10_000, mode: "blocking")
        ]
        let snapshot = TodayTestSupport.snapshot(history, requiredInputs: required, withdrawn: ["withdrawn"])
        XCTAssertEqual(snapshot.sessionDirectory.needsYou.map(\.id), ["required"])
        XCTAssertEqual(snapshot.sessionDirectory.working.count, 3)
        XCTAssertEqual(snapshot.sessionDirectory, SessionDirectory(
            history: history, requiredInputs: required, withdrawn: ["withdrawn"], now: now
        ))
    }

    func testSessionKeysHandleTrimmedIDsTargetRepliesAndDirectMessagesWithLabelFallbacks() {
        let history = [
            TodayTestSupport.message("agent", session: " session ", label: " ", branch: "feature"),
            TodayTestSupport.message("reply", session: nil, targetSession: "session", age: 30,
                                     direction: "boss_to_agent", label: nil, branch: nil),
            TodayTestSupport.message("direct", session: " ", targetSession: " ", label: nil, branch: nil),
            TodayTestSupport.message("id-only", session: "abcd-ef12-3456", label: nil, branch: nil),
        ]
        let sessions = TodayTestSupport.snapshot(history).working
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions.first?.id, "session")
        XCTAssertEqual(sessions.first?.projectLabel, "feature")
        XCTAssertEqual(sessions.first?.statusText, "Body reply")
        XCTAssertEqual(sessions.first { $0.id == "direct" }?.projectLabel, "Direct")
        XCTAssertEqual(sessions.first { $0.id == "abcd-ef12-3456" }?.projectLabel, "abcdef12")
    }

    func testEmptyInputAndStableSessionTieOrder() {
        let empty = SessionDirectory(history: [], now: now)
        XCTAssertTrue(empty.needsYou.isEmpty)
        XCTAssertTrue(empty.working.isEmpty)
        XCTAssertTrue(empty.idle.isEmpty)
        let tied = [
            TodayTestSupport.message("b", session: "b"),
            TodayTestSupport.message("a", session: "a"),
        ]
        XCTAssertEqual(TodayTestSupport.snapshot(tied).working.map(\.id), ["a", "b"])
        XCTAssertEqual(TodayTestSupport.snapshot(tied), TodayTestSupport.snapshot(Array(tied.reversed())))
    }
}

final class WorkingFreshnessTests: XCTestCase {
    private let now = TodayTestSupport.now

    func testStaleWorkingStatusIsNotWorkingNow() {
        // Status left at "working" by a session whose last message was two days ago.
        let stale = TodayTestSupport.message("old", session: "stale", age: 2 * 24 * 3600, sessionStatus: "working")
        XCTAssertTrue(TodayTestSupport.snapshot([stale]).working.isEmpty)
    }

    func testWorkingStatusWithinTwoHoursCountsWithoutAHeartbeat() {
        let quiet = TodayTestSupport.message("q", session: "busy", age: 42 * 60, sessionStatus: "working")
        XCTAssertEqual(TodayTestSupport.snapshot([quiet]).working.map(\.id), ["busy"])
    }

    func testHeartbeatDecidesWhenKnown() {
        let quiet = TodayTestSupport.message("q", session: "busy", age: 42 * 60, sessionStatus: "working")
        let fresh = TodaySnapshot(history: [quiet], health: .live(checkedAt: now), coverageComplete: true,
                                  now: now, lastSeen: ["busy": now.addingTimeInterval(-60)])
        XCTAssertEqual(fresh.working.map(\.id), ["busy"])
        let gone = TodaySnapshot(history: [quiet], health: .live(checkedAt: now), coverageComplete: true,
                                 now: now, lastSeen: ["busy": now.addingTimeInterval(-3600)])
        XCTAssertTrue(gone.working.isEmpty)
    }

    func testRecentMessageIsWorkingWhateverTheStatus() {
        let recent = TodayTestSupport.message("r", session: "idle-but-talking", age: 60, sessionStatus: "idle")
        XCTAssertEqual(TodayTestSupport.snapshot([recent]).working.map(\.id), ["idle-but-talking"])
    }
}
