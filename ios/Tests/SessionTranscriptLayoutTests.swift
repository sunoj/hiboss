// Session transcript presentation: bubbles vs system lines, grouping, truncation.
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

    func testNonMessageAndUnknownKindsAreSystemLines() {
        let items = SessionTranscriptLayout.items(from: [
            event(id: "m", seq: 1, kind: "message", at: "2026-08-14T10:00:00Z"),
            event(id: "t", seq: 2, kind: "tool_call", body: "bash", at: "2026-08-14T10:00:05Z"),
            event(id: "u", seq: 3, kind: "future_kind", body: "keep me", at: "2026-08-14T10:00:06Z"),
        ])
        XCTAssertEqual(items.count, 3)
        guard case .bubble = items[0] else { return XCTFail("message stays a bubble") }
        guard case let .system(tool) = items[1] else { return XCTFail("tool_call is a system line") }
        guard case let .system(unknown) = items[2] else { return XCTFail("unknown kind is not dropped") }
        XCTAssertEqual(tool.kind, "tool_call")
        XCTAssertEqual(unknown.kind, "future_kind")
        XCTAssertEqual(SessionTranscriptLayout.systemLabel(for: unknown), "future_kind · keep me")
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
        guard case .system = items[1] else { return XCTFail("system") }
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
