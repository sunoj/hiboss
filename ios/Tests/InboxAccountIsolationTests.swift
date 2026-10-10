// Verifies per-account inbox details are cleared and obsolete requests cannot repopulate them.
// Exports InboxAccountIsolationTests with explicit detail-response barriers.
// Depends on XCTest, HibossKit, and InboxStore; no network or credential storage.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class InboxAccountIsolationTests: XCTestCase {
    func testAccountReplacementClearsOpenedMessagesAndDetailState() async {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: AccountDetailAPI(body: "Previous account"))
        await store.historyTask?.value
        let result = await store.loadMessage("detail")
        XCTAssertEqual(result, .loaded)
        store.settleReply("Answer", for: "detail")
        store.replyConfirmation = "Sent"
        store.replyFeedback["detail"] = "Feedback"
        store.loadError = "Error"
        store.start(api: AccountDetailAPI(body: "Current account"))
        XCTAssertTrue(store.openedMessages.isEmpty)
        XCTAssertNil(store.message(for: "detail"))
        XCTAssertNil(store.reply(to: "detail"))
        XCTAssertTrue(store.withdrawn.isEmpty)
        XCTAssertTrue(store.settledIDs.isEmpty)
        XCTAssertTrue(store.localResolutions.isEmpty)
        XCTAssertTrue(store.replyFeedback.isEmpty)
        XCTAssertNil(store.replyConfirmation)
        XCTAssertNil(store.loadError)
        store.stop()
    }

    func testLatePreviousAccountDetailCannotOverwriteCurrentDetail() async {
        let previous = AccountDetailAPI(body: "Previous account")
        let current = AccountDetailAPI(body: "Current account")
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: previous)
        let started = expectation(description: "previous detail request started")
        await previous.holdDetail(started)
        let request = Task { await store.loadMessage("detail") }
        await fulfillment(of: [started], timeout: 2)
        store.start(api: current)
        let loaded = await store.loadMessage("detail")
        XCTAssertEqual(loaded, .loaded)
        await previous.releaseDetail()
        _ = await request.value
        XCTAssertEqual(store.message(for: "detail")?.body, "Current account")
        XCTAssertEqual(store.reply(to: "detail")?.body, "Current account reply")
        store.stop()
    }

    func testLateDetailAfterSignOutDoesNotRepopulateOpenedMessages() async {
        let previous = AccountDetailAPI(body: "Previous account")
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: previous)
        let started = expectation(description: "detail request started before sign-out")
        await previous.holdDetail(started)
        let request = Task { await store.loadMessage("detail") }
        await fulfillment(of: [started], timeout: 2)
        store.stop()
        await previous.releaseDetail()
        _ = await request.value
        XCTAssertTrue(store.openedMessages.isEmpty)
        XCTAssertNil(store.message(for: "detail"))
        XCTAssertNil(store.reply(to: "detail"))
    }

    func testLatePreviousAccountMissingDetailIsIgnored() async {
        let previous = AccountDetailAPI(body: "Previous account", failure: .missing)
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: previous)
        let started = expectation(description: "missing detail request started")
        await previous.holdDetail(started)
        let request = Task { await store.loadMessage("detail") }
        await fulfillment(of: [started], timeout: 2)
        store.start(api: AccountDetailAPI(body: "Current account"))
        await previous.releaseDetail()
        let result = await request.value
        XCTAssertNotEqual(result, .missing)
        XCTAssertTrue(store.openedMessages.isEmpty)
        store.stop()
    }

    func testLatePreviousAccountTransportErrorIsIgnored() async {
        let previous = AccountDetailAPI(body: "Previous account", failure: .transport)
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: previous)
        let started = expectation(description: "failed detail request started")
        await previous.holdDetail(started)
        let request = Task { await store.loadMessage("detail") }
        await fulfillment(of: [started], timeout: 2)
        store.start(api: AccountDetailAPI(body: "Current account"))
        await previous.releaseDetail()
        let result = await request.value
        if case .failed = result { XCTFail("An obsolete request must not report an error") }
        XCTAssertTrue(store.openedMessages.isEmpty)
        store.stop()
    }

    func testCurrentAccountMissingAndTransportErrorsAreReported() async {
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: AccountDetailAPI(body: "Current account", failure: .missing))
        let missing = await store.loadMessage("detail")
        XCTAssertEqual(missing, .missing)
        store.start(api: AccountDetailAPI(body: "Current account", failure: .transport))
        let failed = await store.loadMessage("detail")
        guard case .failed = failed else {
            store.stop()
            return XCTFail("A current request must report its transport error")
        }
        store.stop()
    }

}

private actor AccountDetailAPI: BossServing {
    enum Failure { case missing, transport }
    let body: String
    let failure: Failure?
    private var started: XCTestExpectation?
    private var response: CheckedContinuation<Void, Never>?

    init(body: String, failure: Failure? = nil) {
        self.body = body
        self.failure = failure
    }
    func holdDetail(_ started: XCTestExpectation) { self.started = started }
    func releaseDetail() {
        response?.resume()
        response = nil
    }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        if let started {
            self.started = nil
            await withCheckedContinuation {
                response = $0
                started.fulfill()
            }
        }
        switch failure {
        case .missing: throw HibossAPIError.requestFailed(status: 404, message: "")
        case .transport: throw URLError(.notConnectedToInternet)
        case nil: break
        }
        let message = HistoryMessage(id: messageID, body: body, direction: "agent_to_boss",
            status: "replied", priority: "normal", createdAt: "2026-10-01T00:00:00Z")
        let reply = HistoryMessage(id: "reply", body: body + " reply", direction: "boss_to_agent",
            status: "sent", priority: "normal", replyTo: messageID.rawValue,
            createdAt: "2026-10-01T00:00:01Z")
        return MessageDetail(message: message, replies: [reply])
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
