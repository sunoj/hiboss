// Holds history replies until after disconnect or replacement-account connection.
// Exports HistoryReplyAccountIsolationTests for accepted, failed, and conflict replies.
// Dependencies: XCTest, OptionFlowStore, and a deterministic BossServing transport.

import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class HistoryReplyAccountIsolationTests: XCTestCase {
    func testLateFailureDoesNotWriteFeedbackAfterReconnect() async {
        await assertReplyIsDropped(outcome: .failure(URLError(.timedOut)))
    }

    func testLateConflictDoesNotWriteFeedbackAfterReconnect() async {
        await assertReplyIsDropped(outcome: .success(.alreadyResolved))
    }

    func testLateAcceptanceIsNotReportedForReplacementAccount() async {
        await assertReplyIsDropped(outcome: .success(.accepted))
    }

    private func assertReplyIsDropped(outcome: Result<ReplyOutcome, Error>) async {
        let started = expectation(description: "reply started")
        let api = HeldHistoryReplyAPI(started: started, outcome: outcome)
        let flow = OptionFlowStore()
        flow.connect(api: api)
        defer { flow.disconnect() }
        let task = Task { await flow.answerHistory("Ship", for: "shared-id") }
        await fulfillment(of: [started], timeout: 2)
        flow.connect(api: HistoryTestAPI([HistoryResponse(messages: [], total: 0)]))
        await api.release()
        let accepted = await task.value
        XCTAssertFalse(accepted)
        XCTAssertTrue(flow.replyFeedback.isEmpty)
    }
}

private actor HeldHistoryReplyAPI: BossServing {
    let started: XCTestExpectation
    let outcome: Result<ReplyOutcome, Error>
    private var gate: CheckedContinuation<Void, Never>?

    init(started: XCTestExpectation, outcome: Result<ReplyOutcome, Error>) {
        self.started = started
        self.outcome = outcome
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { _ in }
    }

    func fetchHistory() async throws -> [HistoryMessage] { [] }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        throw URLError(.badURL)
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        await withCheckedContinuation {
            gate = $0
            started.fulfill()
        }
        return try outcome.get()
    }
}
