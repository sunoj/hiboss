// Checks cached transcript selection, ordering, automatic outcomes, and unchanged reply gates.
// Exports SessionHistoryTranscriptTests; cached messages use the live renderer's event shape.
// Dependencies: XCTest, HibossKit, InboxStore and SessionReplyTarget.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class SessionHistoryTranscriptTests: XCTestCase {
    func testDirectHistorySelectsOnlyClientBucketInChronologicalOrder() {
        let messages = [message("later", date: "2026-10-11T10:00:00Z"),
                        message("other", session: "live"),
                        message("earlier", date: "2026-10-11T09:00:00Z", session: "  ")]
        let events = SessionHistoryTranscript.events(sessionID: "direct", messages: messages)
        XCTAssertEqual(events.map(\.messageId), ["earlier", "later"])
        XCTAssertEqual(events.map(\.sequence), [1, 2])
        XCTAssertEqual(events.map(\.kind), ["message", "message"])
    }

    func testEndedHistoryUsesGroupingKeyIncludingBossReplyTarget() {
        let messages = [message("question", session: " ended "),
                        message("answer", target: "ended", direction: "boss_to_agent"),
                        message("different", session: "other", target: "ended")]
        let events = SessionHistoryTranscript.events(sessionID: "ended", messages: messages)
        XCTAssertEqual(events.map(\.messageId), ["question", "answer"])
        XCTAssertEqual(events.last?.direction, "boss_to_agent")
        XCTAssertEqual(events.first?.displayBody, "question")
    }

    func testAutomaticReplyRetainsItsTranscriptProvenance() {
        let automatic = HistoryMessage(id: "auto", body: "No", direction: "boss_to_agent",
                                       status: "sent", priority: "normal",
                                       metadata: MessageMetadata(options: [], isAutoDefault: true),
                                       createdAt: "",
                                       targetSessionId: "ended")
        let events = SessionHistoryTranscript.events(sessionID: "ended", messages: [automatic])
        XCTAssertTrue(events.first?.isAutoDefaultReply == true)
        guard case .automatic = SessionTranscriptLayout.items(from: events).first else {
            return XCTFail("An automatic answer must retain the automatic reply row")
        }
    }

    func testHistoryFallbackDoesNotMakeRetiredDecisionsEligible() {
        let store = InboxStore(decisionAlertsEnabled: false)
        let decision = HistoryMessage(id: "decision", body: "Deploy?", direction: "agent_to_boss",
                                      status: "delivered", priority: "normal", mode: "blocking",
                                      metadata: MessageMetadata(options: ["Yes", "No"]), createdAt: "")
        store.history = [decision, message("update")]
        let events = SessionHistoryTranscript.events(sessionID: "direct", messages: store.history)
        XCTAssertTrue(SessionReplyTarget.eligible(events: events, store: store).isEmpty)
        store.requiredInputLoaded = true
        XCTAssertEqual(SessionReplyTarget.eligible(events: events, store: store).map(\.id), ["update"])
        store.requiredInputs = [decision]
        XCTAssertEqual(SessionReplyTarget.eligible(events: events, store: store).map(\.id),
                       ["decision", "update"])
        store.settleReply("No", for: decision.id)
        XCTAssertEqual(SessionReplyTarget.eligible(events: events, store: store).map(\.id), ["update"])
    }

    private func message(_ id: MessageID, date: String = "", session: String? = nil,
                         target: String? = nil, direction: String = "agent_to_boss") -> HistoryMessage {
        HistoryMessage(id: id, body: id.rawValue, agentName: "worker", direction: direction,
                       status: "delivered", priority: "normal", createdAt: date,
                       sessionId: session, targetSessionId: target)
    }
}
