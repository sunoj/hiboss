// Notification-opened detail replies through the injected flow callback, keyed by the loaded id.
// Exports: NotificationReplyE2ETests over accepted, closed-decision and failed outcomes.
// Dependencies: XCTest, NotificationMessageDetail, OptionFlowStore.answer, OutcomeScriptAPI.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class NotificationReplyE2ETests: XCTestCase {

    func testAcceptedReplyReachesServerUnderLoadedIdAndClearsOnlyItsDraft() async throws {
        let api = OutcomeScriptAPI(questions: ["q"], steps: [.accept])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["q"] = "Ship it"
        reply.drafts["other"] = "Keep this draft"

        let feedback = try await send(reply.drafts["q"] ?? "", to: "q", flow: flow, reply: reply)

        XCTAssertNil(feedback)
        let recorded = await api.recordedReplies
        XCTAssertEqual(recorded, [RecordedReply(messageID: "q", choice: "Ship it")])
        XCTAssertNil(reply.drafts["q"])
        XCTAssertNil(reply.errors["q"])
        XCTAssertEqual(reply.drafts["other"], "Keep this draft")
        XCTAssertEqual(flow.historyMessages.first { $0.id == "q" }?.status, "replied")
    }

    func testClosedDecisionAndFailureKeepDraftsWithTypedFeedback() async throws {
        let api = OutcomeScriptAPI(questions: ["a", "b"], steps: [.conflictUnrecorded, .fail])
        let flow = try await connected(api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["a"] = "Hold until Monday"
        reply.drafts["b"] = "Roll back first"

        let closed = try await send("Hold until Monday", to: "a", flow: flow, reply: reply)
        let failed = try await send("Roll back first", to: "b", flow: flow, reply: reply)

        XCTAssertEqual(closed, .alreadyResolved)
        XCTAssertEqual(reply.errors["a"]?.text, L("That decision is no longer available."))
        XCTAssertEqual(reply.drafts["a"], "Hold until Monday")
        XCTAssertEqual(failed, .failed("The reply was rejected."))
        XCTAssertEqual(reply.errors["b"]?.text, L("Reply failed. Your draft is saved. Try again."))
        XCTAssertEqual(reply.drafts["b"], "Roll back first")
        let recorded = await api.recordedReplies
        XCTAssertEqual(recorded.map(\.messageID), ["a", "b"])
    }

    func testLoadedNotificationDetailKeepsTheReturnedThreadReplies() throws {
        let parent = HistoryMessage(id: "q", body: "Ship?", direction: "agent_to_boss",
            status: "replied", priority: "normal", metadata: MessageMetadata(options: ["Ship", "Hold"]),
            createdAt: "2026-10-08T10:00:00Z")
        let answer = HistoryMessage(id: "answer", body: "Hold", direction: "boss_to_agent",
            status: "sent", priority: "normal", replyTo: "q",
            metadata: MessageMetadata(options: [], isAutoDefault: true), createdAt: "2026-10-08T10:01:00Z")
        let view = NotificationMessageDetail(messageID: "stale", settings: try settings(),
            reply: AttentionReplyState(), onReply: { _, _ in nil })
        let detail = view.loadedDetail(parent, replies: [answer])
        XCTAssertEqual(detail.message.id, "q")
        XCTAssertEqual(detail.replies, [answer])
        XCTAssertEqual(MessageThread(message: detail.message, replies: detail.replies).outcome,
            .autoSelected(option: "Hold"))
    }

    /// Builds the notification detail with a stale requested id, then sends through the
    /// loaded HistoryMessageDetail's own callback, as its composer and choice buttons do.
    private func send(
        _ text: String, to id: MessageID, flow: OptionFlowStore, reply: AttentionReplyState
    ) async throws -> ReplyFeedback? {
        let message = try XCTUnwrap(flow.historyMessages.first { $0.id == id })
        let view = NotificationMessageDetail(messageID: "stale-notification-id", settings: try settings(),
            reply: reply, onReply: flow.answer)
        let detail = view.loadedDetail(message)
        var feedback: ReplyFeedback?
        await reply.send(text, for: detail.message.id) { text, _ in
            feedback = await detail.onChoose(text)
            return feedback
        }
        return feedback
    }

    private func connected(_ api: OutcomeScriptAPI) async throws -> OptionFlowStore {
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        flow.connect(api: api)
        try await waitForCondition { flow.historyState == .loaded }
        return flow
    }

    private func settings() throws -> AppSettings {
        let suiteName = "NotificationReplyE2ETests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return AppSettings(defaults: defaults, keychain: EmptyTokenStore())
    }
}

private struct EmptyTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
