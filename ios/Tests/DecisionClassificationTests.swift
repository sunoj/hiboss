// App projections must use HibossKit's decision shape, including uncached session payloads.
// Exports DecisionClassificationTests; verifies reply feedback stays outside history errors.
// Dependencies: InboxStore, MessageRowBadge, SessionReplyTarget, HeldReplyAPI and XCTest.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionClassificationTests: XCTestCase {
    func testBlockingTextDecisionGetsSettlementAndDecisionBadge() {
        let message = Self.message(mode: "blocking")
        let store = InboxStore(decisionAlertsEnabled: false)
        store.history = [message, HistoryMessage(
            id: "reply", body: "Dataset A", direction: "boss_to_agent", status: "sent",
            priority: "normal", replyTo: message.id.rawValue, createdAt: "2026-10-10T00:01:00Z")]
        store.adoptHistoryReplies()
        XCTAssertEqual(store.localResolutions[message.id]?.answer, "Dataset A")
        XCTAssertEqual(MessageRowBadge.badge(for: message, answerability: .checking), .loading)
        XCTAssertEqual(MessageRowBadge.badge(for: message, answerability: .open), .decisionNeeded)
    }

    func testAsyncApprovalTypeIsOrdinaryInBadgesAndCachedAndUncachedReplyTargets() {
        let message = Self.message(mode: "async")
        XCTAssertNil(MessageRowBadge.badge(for: message, answerability: .checking))
        let event = SessionEvent(
            id: "event", sessionId: "session", sequence: 1, kind: "message", direction: "agent_to_boss",
            messageId: message.id.rawValue,
            payload: .object(["body": .string(message.body), "mode": .string("async"),
                              "type": .string("approval_request")]), createdAt: message.createdAt)
        let store = InboxStore(decisionAlertsEnabled: false)
        store.requiredInputLoaded = true
        for history in [[message], []] {
            store.history = history
            let targets = SessionReplyTarget.eligible(events: [event], store: store)
            XCTAssertEqual(targets.map(\.id), [message.id])
            XCTAssertEqual(targets.first?.isDecision, false)
        }
    }

    func testUncachedBlockingPayloadIsStillAClosedDecision() {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.requiredInputLoaded = true
        let event = SessionEvent(
            id: "event", sessionId: "session", sequence: 1, kind: "message", direction: "agent_to_boss",
            messageId: "missing", payload: .object(["body": .string("Choose?"),
                                                    "mode": .string("blocking")]), createdAt: "")
        XCTAssertTrue(SessionReplyTarget.eligible(events: [event], store: store).isEmpty)
    }

    func testCheckingReplyDoesNotCreateOrOverwriteHistoryError() async {
        let message = Self.message(mode: "blocking")
        let api = HeldReplyAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.history = [message]
        for historyError in [nil, "History unavailable"] as [String?] {
            store.loadError = historyError
            let feedback = await store.replyWithFeedback("Dataset A", to: message.id)
            XCTAssertEqual(feedback, String(localized: "Checking…"))
            XCTAssertEqual(store.loadError, historyError)
            XCTAssertTrue(api.replies.isEmpty)
        }
        XCTAssertEqual(store.replyFeedback[message.id], String(localized: "Checking…"))
        XCTAssertNil(store.replyFeedback["another-decision"])
        store.requiredInputLoaded = true
        let result = await store.reply("Dataset A", to: message.id)
        XCTAssertEqual(result, .alreadyResolved)
        XCTAssertNil(store.replyFeedback[message.id])
    }

    func testExternalReplyGateAllowsAsyncApprovalWithoutTreatingItAsRetired() async throws {
        let message = Self.message(mode: "async")
        let api = HeldReplyAPI(detail: MessageDetail(message: message, replies: []), requiredInputs: [])
        let gate = DecisionReplyGate()
        let reply = Pending { await gate.submit("Acknowledged", to: message.id, via: api) }
        await waitUntil { reply.isDone || !api.replies.isEmpty }
        api.release()
        let result = try await reply.settled()
        XCTAssertEqual(result, .accepted)
        XCTAssertEqual(api.replies, ["Acknowledged"])
    }

    private static func message(mode: String) -> HistoryMessage {
        HistoryMessage(id: "text", body: "Which dataset?", direction: "agent_to_boss", status: "sent",
                       priority: "normal", mode: mode, type: "approval_request",
                       createdAt: "2026-10-10T00:00:00Z", sessionId: "session")
    }
}
