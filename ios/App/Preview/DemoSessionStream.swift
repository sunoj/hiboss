// Demo session-stream extras: mixed directions plus non-message kinds for UI shots.
// Exports: DemoSessionStream projecting history messages and splicing system events.
// Dependencies: Foundation, HibossKit SessionEvent / HistoryMessage.

import Foundation
import HibossKit

enum DemoSessionStream {
    static func events(for sessionID: String, from messages: [HistoryMessage]) -> [SessionEvent] {
        let projected = messages
            .filter { $0.sessionId == sessionID || $0.targetSessionId == sessionID }
            .sorted { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) }
            .enumerated()
            .map { index, message in project(message, sessionID: sessionID, sequence: index + 1) }
        guard sessionID == "sess-deploy" else { return projected }
        return spliceNonMessageEvents(into: projected)
    }

    private static func project(_ message: HistoryMessage, sessionID: String, sequence: Int) -> SessionEvent {
        SessionEvent(
            id: "evt-\(message.id.rawValue)", sessionId: sessionID, sequence: sequence,
            kind: "message", direction: message.direction, actorName: message.agentName,
            messageId: message.id.rawValue,
            payload: .object(["body": .string(message.body), "priority": .string(message.priority)]),
            createdAt: message.createdAt
        )
    }

    private static func spliceNonMessageEvents(into events: [SessionEvent]) -> [SessionEvent] {
        var result: [SessionEvent] = []
        for event in events {
            result.append(event)
            if event.messageId == "r0" {
                result.append(contentsOf: stagingSideband(after: event))
            }
        }
        return result.enumerated().map { index, event in
            copy(event, sequence: index + 1)
        }
    }

    private static func stagingSideband(after event: SessionEvent) -> [SessionEvent] {
        let sid = event.sessionId
        let actor = event.actorName
        let when = event.createdAt
        return [
            SessionEvent(
                id: "evt-tool-call", sessionId: sid, sequence: 0, kind: "tool_call",
                direction: "agent_to_boss", actorName: actor,
                payload: .object(["body": .string("xcodebuild test -scheme HiBoss"), "tool": .string("bash")]),
                createdAt: when
            ),
            SessionEvent(
                id: "evt-tool-result", sessionId: sid, sequence: 0, kind: "tool_result",
                direction: "agent_to_boss", actorName: actor,
                payload: .object(["body": .string(Self.longToolOutput)]),
                createdAt: when
            ),
            SessionEvent(
                id: "evt-hook", sessionId: sid, sequence: 0, kind: "hook",
                direction: "agent_to_boss", actorName: actor,
                payload: .object(["summary": .string("SessionStart completed")]),
                createdAt: when
            ),
            SessionEvent(
                id: "evt-unknown", sessionId: sid, sequence: 0, kind: "future_kind",
                actorName: actor,
                payload: .object(["note": .string("kept by fallback")]),
                createdAt: when
            ),
        ]
    }

    private static func copy(_ event: SessionEvent, sequence: Int) -> SessionEvent {
        SessionEvent(
            id: event.id, sessionId: event.sessionId, sequence: sequence,
            kind: event.kind, direction: event.direction,
            actorAgentId: event.actorAgentId, actorName: event.actorName,
            targetAgentId: event.targetAgentId, messageId: event.messageId,
            source: event.source, payload: event.payload, raw: event.raw,
            createdAt: event.createdAt
        )
    }

    private static let longToolOutput = """
    Test Suite 'All Tests' started.
    Test Suite 'HiBossTests.xctest' started.
    Test Case '-[HiBossTests.InboxStoreTests testReplySettlesCardInPlaceAndKeepsBossReplyInSession]' passed (0.041 seconds).
    Test Case '-[HiBossTests.SessionTranscriptLayoutTests testUnknownKindRendersAsSystemLine]' passed (0.002 seconds).
    ** TEST SUCCEEDED ** 34 tests, 0 failures, 214 assertions. Full log retained for the operator.
    """
}
