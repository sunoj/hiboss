// Session transcript presentation: bubbles vs collapsed step runs, grouping, truncation.
// Exports: SessionTranscriptLayoutTests.
// Dependencies: XCTest, HiBoss app target, HibossKit SessionEvent.

import HibossKit
import XCTest
@testable import HiBoss

final class SessionTranscriptLayoutTests: XCTestCase {
    func testMessagesBecomeOutgoingAndIncomingBubbles() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "a", seq: 1, kind: "message", direction: "agent_to_boss", at: "2026-08-14T10:00:00Z"),
            event(id: "b", seq: 2, kind: "message", direction: "boss_to_agent", at: "2026-08-14T10:00:10Z"),
        ])
        XCTAssertEqual(items.count, 2)
        guard case let .bubble(incoming, inStyle) = items[0] else { return XCTFail("incoming bubble") }
        guard case let .bubble(outgoing, outStyle) = items[1] else { return XCTFail("outgoing bubble") }
        XCTAssertEqual(incoming.id, "a")
        XCTAssertFalse(inStyle.isOutgoing)
        XCTAssertTrue(inStyle.showsSender)
        XCTAssertTrue(inStyle.isLastInGroup)
        XCTAssertEqual(outgoing.id, "b")
        XCTAssertTrue(outStyle.isOutgoing)
        XCTAssertFalse(outStyle.showsSender)
    }

    func testConsecutiveSameSenderGroupsWithoutTailOnEarlier() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "a1", seq: 1, kind: "message", actor: "worker", at: "2026-08-14T10:00:00Z"),
            event(id: "a2", seq: 2, kind: "message", actor: "worker", at: "2026-08-14T10:00:20Z"),
        ])
        XCTAssertEqual(items.count, 2)
        guard case let .bubble(_, first) = items[0] else { return XCTFail("first") }
        guard case let .bubble(_, last) = items[1] else { return XCTFail("last") }
        XCTAssertTrue(first.isFirstInGroup)
        XCTAssertFalse(first.isLastInGroup)
        XCTAssertTrue(first.showsSender)
        XCTAssertFalse(last.isFirstInGroup)
        XCTAssertTrue(last.isLastInGroup)
        XCTAssertFalse(last.showsSender)
    }

    func testConsecutiveActivityCollapsesIntoOneStepsRunAndUnknownKindsAreSkipped() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "m1", seq: 1, kind: "message", at: "2026-08-14T10:00:00Z"),
            event(id: "t", seq: 2, kind: "tool_call", body: "bash", at: "2026-08-14T10:00:05Z"),
            event(id: "r", seq: 3, kind: "tool_result", body: "ok", at: "2026-08-14T10:00:06Z"),
            event(id: "u", seq: 4, kind: "future_kind", body: "raw", at: "2026-08-14T10:00:07Z"),
            event(id: "h", seq: 5, kind: "hook", body: "SessionStart", at: "2026-08-14T10:00:08Z"),
            event(id: "m2", seq: 6, kind: "message", at: "2026-08-14T10:00:09Z"),
            event(id: "e", seq: 7, kind: "error", body: "boom", at: "2026-08-14T10:00:10Z"),
        ])
        XCTAssertEqual(items.map(\.id), ["m1", "steps-t", "m2", "e"])
        guard case let .steps(_, run) = items[1] else { return XCTFail("activity collapses into one run") }
        XCTAssertEqual(run.map(\.id), ["t", "r", "h"], "unknown kinds never appear, not even inside the run")
        guard case .notice = items[3] else { return XCTFail("an agent error stays visible, never folded into steps") }
    }

    func testOnlyUnknownKindsProduceNoRow() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "u", seq: 1, kind: "future_kind", at: "2026-08-14T10:00:00Z"),
        ])
        XCTAssertTrue(items.isEmpty)
    }

    func testTimeSeparatorSplitsAStepsRun() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "t1", seq: 1, kind: "tool_call", at: "2026-08-14T10:00:00Z"),
            event(id: "t2", seq: 2, kind: "tool_call", at: "2026-08-14T12:00:00Z"),
        ])
        XCTAssertEqual(items.map(\.id), ["steps-t1", "time-t2", "steps-t2"])
    }

    func testDistantGapInsertsTimeSeparatorAndBreaksGroup() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "a1", seq: 1, kind: "message", actor: "worker", at: "2026-08-14T10:00:00Z"),
            event(id: "a2", seq: 2, kind: "message", actor: "worker", at: "2026-08-14T12:00:00Z"),
        ])
        XCTAssertEqual(items.count, 3)
        guard case .time = items[1] else { return XCTFail("time separator") }
        guard case let .bubble(_, first) = items[0] else { return XCTFail("first") }
        guard case let .bubble(_, later) = items[2] else { return XCTFail("later") }
        XCTAssertTrue(first.isLastInGroup)
        XCTAssertTrue(later.isFirstInGroup)
        XCTAssertTrue(later.showsSender)
    }

    func testSystemEventBreaksMessageGroup() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "a1", seq: 1, kind: "message", actor: "worker", at: "2026-08-14T10:00:00Z"),
            event(id: "s", seq: 2, kind: "system", body: "compacted", at: "2026-08-14T10:00:05Z"),
            event(id: "a2", seq: 3, kind: "message", actor: "worker", at: "2026-08-14T10:00:10Z"),
        ])
        guard case let .bubble(_, first) = items[0] else { return XCTFail("first") }
        guard case .steps = items[1] else { return XCTFail("steps") }
        guard case let .bubble(_, after) = items[2] else { return XCTFail("after") }
        XCTAssertTrue(first.isLastInGroup)
        XCTAssertTrue(after.isFirstInGroup)
    }

    func testCollapsedLongPayloadKeepsShortTextAndEllipsizesLong() {
        XCTAssertEqual(SessionTranscriptLayout.collapsed("short"), "short")
        let long = String(repeating: "a", count: SessionTranscriptLayout.collapseLimit + 8)
        let clipped = SessionTranscriptLayout.collapsed(long)
        XCTAssertEqual(clipped.count, SessionTranscriptLayout.collapseLimit + 1)
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertFalse(clipped.contains(String(repeating: "a", count: SessionTranscriptLayout.collapseLimit + 1)))
    }

    private func event(
        id: String,
        seq: Int,
        kind: String,
        direction: String? = "agent_to_boss",
        actor: String? = "worker",
        body: String = "hello",
        at: String
    ) -> SessionEvent {
        SessionEvent(
            id: id, sessionId: "s", sequence: seq, kind: kind, direction: direction,
            actorName: actor, payload: .object(["body": .string(body)]), createdAt: at
        )
    }
}
