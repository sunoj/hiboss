// One reply per decision in flight, whichever surface sends it: Home, detail, transcript,
// notification actions and Live Activity intents all pass DecisionReplyGate.
// Exports: DecisionReplyGateTests and DecisionConflictTests, including production HTTP 409 coverage.
// Dependencies: XCTest, Foundation, HiBoss app target, HeldReplyAPI and Pending.

import Combine
import Foundation
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionReplyGateTests: XCTestCase {
    private func makeStore(_ api: HeldReplyAPI, gate: DecisionReplyGate = DecisionReplyGate())
        async -> InboxStore {
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false,
                               replyGate: gate)
        store.start(api: api)
        await waitUntil { store.hasCompleteRequiredInputs }
        XCTAssertTrue(store.hasCompleteRequiredInputs)
        return store
    }

    // Every test releases only after the fake has recorded the reply, and awaits through
    // `Pending.settled()`, so a missing guard or a lost release fails rather than hangs.

    func testAccountReplacementResetsSharedReplyAndIgnoresOldCompletion() async throws {
        let gate = DecisionReplyGate()
        let previous = HeldReplyAPI()
        let current = HeldReplyAPI()
        let store = await makeStore(previous, gate: gate)
        defer { store.stop() }
        let oldReply = Pending { await gate.submit("Approve", to: "q1", via: previous) }
        await waitUntil { previous.replies.count == 1 }
        XCTAssertEqual(store.replying["q1"], "Approve")

        store.start(api: current)
        await waitUntil { store.hasCompleteRequiredInputs }
        XCTAssertTrue(store.replying.isEmpty, "a new account has no inherited submissions")
        let newReply = Pending { await store.reply("Approve", to: "q1") }
        await waitUntil { newReply.isDone || current.replies.count == 1 }
        XCTAssertEqual(current.replies, ["Approve"], "the same ID is admitted for the new account")

        previous.release()
        _ = try await oldReply.settled()
        XCTAssertEqual(store.replying["q1"], "Approve", "an old completion cannot release the new slot")
        XCTAssertTrue(store.withdrawn.isEmpty)
        XCTAssertNil(store.replyConfirmation)
        current.release()
        let result = try await newReply.settled()
        XCTAssertEqual(result, .sent)
        XCTAssertTrue(store.replying.isEmpty)
    }

    func testAcceptedReplyShowsServerDeviceBeforeHistoryRefresh() async throws {
        let api = HeldReplyAPI()
        let store = await makeStore(api)
        defer { store.stop() }
        let reply = Pending { await store.reply("Approve", to: "q1") }
        await waitUntil { api.replies.count == 1 }
        let device = AnsweringDevice(clientID: "phone", kind: "ios", label: "Ming's iPhone")
        api.release(.success(.acceptedOn(device)))
        let result = try await reply.settled()
        XCTAssertEqual(result, .sent)
        XCTAssertEqual(store.localResolutions["q1"]?.sourceLabel, device.label)
    }

    func testSignOutIgnoresOldInAppReplyFailure() async throws {
        let api = HeldReplyAPI()
        let store = await makeStore(api)
        let reply = Pending { await store.reply("Approve", to: "q1") }
        await waitUntil { api.replies.count == 1 }
        store.stop()
        XCTAssertTrue(store.replying.isEmpty)
        api.release(.failure(URLError(.timedOut)))
        _ = try await reply.settled()
        XCTAssertTrue(store.replying.isEmpty)
        XCTAssertNil(store.loadError)
        XCTAssertTrue(store.localResolutions.isEmpty)
    }

    func testAccountReplacementIgnoresOldInAppReplySuccess() async throws {
        let previous = HeldReplyAPI()
        let current = HeldReplyAPI()
        let store = await makeStore(previous)
        defer { store.stop() }
        let reply = Pending { await store.reply("Approve", to: "q1") }
        await waitUntil { previous.replies.count == 1 }
        store.start(api: current)
        previous.release()
        _ = try await reply.settled()

        XCTAssertTrue(store.replying.isEmpty)
        XCTAssertTrue(store.withdrawn.isEmpty)
        XCTAssertTrue(store.localResolutions.isEmpty)
        XCTAssertNil(store.replyConfirmation)
        XCTAssertNil(store.loadError)
    }

    func testOldAuthorizationRejectionCannotClearTheNewAccount() async throws {
        for status in [401, 403] {
            let previous = HeldReplyAPI()
            let current = HeldReplyAPI()
            let store = await makeStore(previous)
            let reply = Pending { await store.reply("Approve", to: "q1") }
            await waitUntil { previous.replies.count == 1 }
            store.start(api: current)
            await waitUntil { store.hasCompleteRequiredInputs }
            previous.release(.failure(HibossAPIError.requestFailed(status: status, message: "Rejected")))
            _ = try await reply.settled()
            XCTAssertTrue(store.hasCompleteRequiredInputs)
            XCTAssertTrue(store.requiredInputLoaded)
            XCTAssertTrue(store.isReady)
            store.stop()
        }
    }

    func testSecondTapWhileReplyIsInFlightSendsNothing() async throws {
        let api = HeldReplyAPI()
        let store = await makeStore(api)
        let first = Pending { await store.replyWithFeedback("Approve", to: "q1") }
        await waitUntil { api.replies.count == 1 }
        XCTAssertEqual(store.replying["q1"], "Approve", "the in-flight choice is published for the buttons")

        let second = Pending { await store.replyWithFeedback("Reject", to: "q1") }
        // Bounded: a guard returns at once; a regression records a second reply instead.
        await waitUntil { second.isDone || api.replies.count > 1 }
        api.release()
        let secondNote = try await second.settled()
        let firstNote = try await first.settled()

        XCTAssertEqual(api.replies, ["Approve"])
        XCTAssertNil(secondNote, "an ignored tap shows no note")
        XCTAssertNil(firstNote)
        XCTAssertNil(store.replying["q1"])
    }

    func testDetailCannotSubmitWhileHomeReplyIsInFlight() async throws {
        let api = HeldReplyAPI()
        let store = await makeStore(api)
        let home = Pending { await store.replyWithFeedback("Approve", to: "q1") }
        await waitUntil { api.replies.count == 1 }

        let detail = Pending { await store.reply("Reject", to: "q1") }
        await waitUntil { detail.isDone || api.replies.count > 1 }
        api.release()
        let detailResult = try await detail.settled()
        _ = try await home.settled()

        XCTAssertEqual(detailResult, .busy, "detail's reply path is admitted by the same gate")
        XCTAssertEqual(api.replies, ["Approve"])
    }

    func testIndependentDecisionsAreAdmittedTogether() async throws {
        let api = HeldReplyAPI()
        let store = await makeStore(api)
        let first = Pending { await store.reply("Approve", to: "q1") }
        let second = Pending { await store.reply("Hold", to: "q2") }
        await waitUntil { api.replies.count == 2 }
        XCTAssertEqual(store.replying, ["q1": "Approve", "q2": "Hold"])
        api.release()
        let results = [try await first.settled(), try await second.settled()]
        XCTAssertEqual(results, [.sent, .sent])
        XCTAssertTrue(store.replying.isEmpty)
    }

    func testFailureReleasesTheDecisionForARetry() async throws {
        let api = HeldReplyAPI()
        let store = await makeStore(api)
        let failing = Pending { await store.reply("Approve", to: "q1") }
        await waitUntil { api.replies.count == 1 }
        api.release(.failure(URLError(.timedOut)))
        let failed = try await failing.settled()
        XCTAssertEqual(failed, .failed)
        XCTAssertNil(store.replying["q1"], "a failure frees the buttons")

        let retry = Pending { await store.reply("Approve", to: "q1") }
        await waitUntil { api.replies.count == 2 }
        api.release()
        let retried = try await retry.settled()
        XCTAssertEqual(retried, .sent, "the retry is admitted")
    }

    func testCancellationReleasesTheDecision() async {
        let api = HeldReplyAPI()
        let store = await makeStore(api)
        let task = Task { await store.reply("Approve", to: "q1") }
        await waitUntil { api.replies.count == 1 }
        task.cancel()
        let result = await task.value  // the fake resumes a cancelled reply, so this returns
        XCTAssertEqual(result, .failed)
        XCTAssertNil(store.replying["q1"], "a cancelled reply frees the buttons")
    }

    func testGateChangesRepublishTheStoreForEveryButtonSurface() async throws {
        let gate = DecisionReplyGate()
        let api = HeldReplyAPI()
        let store = await makeStore(api, gate: gate)
        var changes = 0
        let observation = store.objectWillChange.sink { _ in changes += 1 }
        let task = Pending { await gate.submit("Approve", to: "q1", via: api) }
        await waitUntil { changes > 0 && api.replies.count == 1 }
        XCTAssertGreaterThan(changes, 0, "views observing the store re-render when a reply starts")
        api.release()
        _ = try await task.settled()
        observation.cancel()
    }
}

@MainActor
final class DecisionConflictTests: XCTestCase {
    func testDecisionNoLongerOpenConflictClosesTextDecision() async throws {
        try await assertConflictClosesDecision(options: [])
    }

    func testOptionConflictClosesOptionDecision() async throws {
        try await assertConflictClosesDecision(options: ["Yes", "No"])
    }

    private func assertConflictClosesDecision(options: [String]) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DecisionConflictURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://decision.example")), bossToken: "test-token"
        ), session: session)
        let store = InboxStore(decisionAlertsEnabled: false, replyGate: DecisionReplyGate())
        store.api = api
        defer { store.stop() }
        let decision = HistoryMessage(
            id: options.isEmpty ? "text" : "option", body: "Proceed?", direction: "agent_to_boss",
            status: "sent", priority: "high", mode: "blocking",
            metadata: MessageMetadata(options: options), createdAt: ""
        )
        let other = HistoryMessage(id: "other", body: "Another decision?", direction: "agent_to_boss",
                                   status: "sent", priority: "low", mode: "blocking", createdAt: "")
        store.history = [decision, other]
        store.requiredInputs = [decision, other]
        store.requiredInputLoaded = true
        store.requiredInputReady = true
        XCTAssertEqual(store.answerability(for: decision.id), .open)
        let result = await store.reply("Yes", to: decision.id)
        XCTAssertEqual(result, .alreadyResolved)
        XCTAssertEqual(store.answerability(for: decision.id), .closed)
        XCTAssertEqual(store.answerability(for: decision.id).label, "No longer open")
        XCTAssertEqual(store.answerability(for: other.id), .open)
        XCTAssertNil(store.localResolutions[decision.id], "a conflict must not invent an answer")
        await store.refresh()
        store.requiredInputs = [decision, other]
        store.requiredInputLoaded = true
        store.requiredInputReady = true
        XCTAssertEqual(store.answerability(for: decision.id), .closed, "a stale snapshot cannot reopen it")
    }
}

private final class DecisionConflictURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return XCTFail("Missing request URL") }
        let isReply = url.lastPathComponent == "reply"
        let body: String
        if isReply {
            XCTAssertEqual(request.httpMethod, "POST")
            body = url.path.contains("/text/")
                ? #"{"error":"decision no longer open"}"#
                : #"{"error":"options already resolved"}"#
        } else {
            body = #"{"messages":[]}"#
        }
        guard let response = HTTPURLResponse(url: url, statusCode: isReply ? 409 : 200,
                                            httpVersion: nil, headerFields: nil) else {
            return XCTFail("Invalid response URL")
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
