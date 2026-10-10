// Verifies accepted reply feedback does not wait for history synchronization.
// Exports OptionReplyFeedbackTests for live choices and history replies.
// Depends on OptionFlowStore and a deterministic API with a held history fetch.

import XCTest
@testable import HibossKit

@MainActor
final class OptionReplyFeedbackTests: XCTestCase {
    func testAcceptedLiveChoiceResolvesWhileHistoryIsHeld() async throws {
        try await assertAcceptedReplyDoesNotWaitForHistory(active: true)
    }

    func testAcceptedHistoryReplyReturnsWhileHistoryIsHeld() async throws {
        try await assertAcceptedReplyDoesNotWaitForHistory(active: false)
    }

    private func assertAcceptedReplyDoesNotWaitForHistory(active: Bool) async throws {
        let api = HeldReplyHistoryAPI()
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitUntil { flow.historyState == .loaded && flow.activeMessage?.id == "live" }
        await api.holdHistory()
        var completed = false
        let reply = Task {
            let accepted = active
                ? await flow.choose("Ship", for: "live")
                : await flow.answerHistory("Ship", for: "history")
            completed = true
            return accepted
        }
        try await waitUntil { await api.isHistoryHeld }
        XCTAssertTrue(completed, "Acceptance must return while the background history fetch is held")
        if active {
            XCTAssertEqual(flow.activeMessage?.id, "live")
            XCTAssertEqual(flow.presentationState, .resolved(answer: "Ship", source: "Mac"))
        } else {
            XCTAssertEqual(flow.activeMessage?.id, "live")
            XCTAssertEqual(flow.presentationState, .ready)
        }
        await api.releaseHistory()
        let accepted = await reply.value
        XCTAssertTrue(accepted)
        try await waitUntil { flow.historyMessages.first?.id == "refreshed" }
        XCTAssertEqual(flow.historyState, .loaded)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) {
            if ContinuousClock.now >= deadline { throw FeedbackTestError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private enum FeedbackTestError: Error {
    case timeout
}

private actor HeldReplyHistoryAPI: BossServing {
    private var holdingHistory = false
    private var continuation: CheckedContinuation<Void, Never>?
    var isHistoryHeld: Bool { continuation != nil }

    func holdHistory() { holdingHistory = true }

    func releaseHistory() {
        holdingHistory = false
        continuation?.resume()
        continuation = nil
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream {
            $0.yield(.message(OptionMessage(id: "live", body: "Choose?",
                metadata: MessageMetadata(options: ["Ship", "Wait"]))))
        }
    }

    func fetchHistory() async throws -> [HistoryMessage] {
        guard holdingHistory else { return [] }
        await withCheckedContinuation { continuation = $0 }
        return [HistoryMessage(id: "refreshed", body: "History caught up", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "2026-10-10T12:00:00Z")]
    }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        throw FeedbackTestError.timeout
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
