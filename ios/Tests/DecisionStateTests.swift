// Decision-state tests: timeout defaults are attributed to the server, one reply per decision
// is in flight, and a failed refresh over loaded rows is reported as stale.
// Exports: DecisionStateTests. Dependencies: XCTest, HiBoss app target, HibossKit BossServing.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionStateTests: XCTestCase {
    func testSystemReplyIsAnAutoDefaultNotAnAnswerFromElsewhere() {
        let automatic = DecisionSettlement(answer: "Keep current key", source: "system")
        XCTAssertTrue(automatic.isAutoDefault)
        XCTAssertFalse(automatic.answeredElsewhere)
        XCTAssertEqual(automatic.symbol, "clock.arrow.circlepath")

        let telegram = DecisionSettlement(answer: "Hold", source: "telegram")
        XCTAssertFalse(telegram.isAutoDefault)
        XCTAssertTrue(telegram.answeredElsewhere)
        XCTAssertEqual(telegram.symbol, "checkmark.circle.fill")

        XCTAssertFalse(DecisionSettlement(answer: "Ship", source: "ios").answeredElsewhere)
        XCTAssertFalse(DecisionSettlement(answer: "Ship", source: nil).isAutoDefault)
    }

    func testListPhaseKeepsRowsAndReportsAFailedRefresh() {
        XCTAssertEqual(ListStatePhase.resolve(isLoading: true, error: nil, isEmpty: true), .loading)
        XCTAssertEqual(ListStatePhase.resolve(isLoading: false, error: "down", isEmpty: true), .unreachable("down"))
        XCTAssertEqual(ListStatePhase.resolve(isLoading: false, error: nil, isEmpty: true), .empty)
        XCTAssertEqual(ListStatePhase.resolve(isLoading: false, error: "down", isEmpty: false),
                       .content(staleError: "down"))
        XCTAssertEqual(ListStatePhase.resolve(isLoading: false, error: nil, isEmpty: false),
                       .content(staleError: nil))
    }

    func testSecondTapWhileReplyIsInFlightSendsNothing() async {
        let api = SlowReplyAPI()
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.start(api: api)
        let first = Task { await store.replyWithFeedback("Approve", to: "q1") }
        for _ in 0..<200 where store.replying["q1"] == nil { await Task.yield() }
        XCTAssertEqual(store.replying["q1"], "Approve", "the in-flight choice is published for the buttons")

        let second = await store.replyWithFeedback("Reject", to: "q1")
        XCTAssertNil(second, "an ignored tap shows no note")
        api.release()
        let firstNote = await first.value

        XCTAssertNil(firstNote)
        XCTAssertEqual(api.replies, ["Approve"])
        XCTAssertNil(store.replying["q1"])
    }
}

/// Holds every reply until `release()`, so a test can act while one is in flight.
private final class SlowReplyAPI: BossServing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    var replies: [String] { lock.withLock { recorded } }

    func release() {
        let waiting: CheckedContinuation<Void, Never>? = lock.withLock {
            released = true
            defer { gate = nil }
            return gate
        }
        waiting?.resume()
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { continuation in continuation.onTermination = { _ in } }
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fetchHistory() async throws -> [HistoryMessage] { [] }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        throw HibossAPIError.requestFailed(status: 404, message: "")
    }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow: Bool = lock.withLock {
                recorded.append(choice)
                if !released { gate = continuation }
                return released
            }
            if resumeNow { continuation.resume() }
        }
        return .accepted
    }
}
