// One reply per decision in flight, whichever surface sends it: Home, detail, transcript,
// notification actions and Live Activity intents all pass DecisionReplyGate.
// Exports: DecisionReplyGateTests. Dependencies: XCTest, HiBoss app target, HeldReplyAPI.

import Combine
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionReplyGateTests: XCTestCase {
    private final class Finished { var value = false }

    private func makeStore(_ api: HeldReplyAPI, gate: DecisionReplyGate = DecisionReplyGate()) -> InboxStore {
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false, replyGate: gate)
        store.start(api: api)
        return store
    }

    func testSecondTapWhileReplyIsInFlightSendsNothing() async {
        let api = HeldReplyAPI()
        let store = makeStore(api)
        let first = Task { await store.replyWithFeedback("Approve", to: "q1") }
        await waitUntil { store.replying["q1"] != nil }
        XCTAssertEqual(store.replying["q1"], "Approve", "the in-flight choice is published for the buttons")

        let done = Finished()
        let second = Task { () -> String? in
            defer { done.value = true }
            return await store.replyWithFeedback("Reject", to: "q1")
        }
        // Bounded: a guard returns at once; a regression records a second reply instead.
        await waitUntil { done.value || api.replies.count > 1 }
        api.release()  // before awaiting either task, so a missing guard fails rather than hangs
        let secondNote = await second.value
        let firstNote = await first.value

        XCTAssertEqual(api.replies, ["Approve"])
        XCTAssertNil(secondNote, "an ignored tap shows no note")
        XCTAssertNil(firstNote)
        XCTAssertNil(store.replying["q1"])
    }

    func testDetailCannotSubmitWhileHomeReplyIsInFlight() async {
        let api = HeldReplyAPI()
        let store = makeStore(api)
        let home = Task { await store.replyWithFeedback("Approve", to: "q1") }
        await waitUntil { store.replying["q1"] != nil }

        let done = Finished()
        let detail = Task { () -> ReplyResult in
            defer { done.value = true }
            return await store.reply("Reject", to: "q1")
        }
        await waitUntil { done.value || api.replies.count > 1 }
        api.release()
        let detailResult = await detail.value
        _ = await home.value

        XCTAssertEqual(detailResult, .busy, "detail's reply path is admitted by the same gate")
        XCTAssertEqual(api.replies, ["Approve"])
    }

    func testNotificationOrIntentReplyIsRefusedAndShownInTheApp() async {
        let gate = DecisionReplyGate()
        let appAPI = HeldReplyAPI(), externalAPI = HeldReplyAPI()
        let store = makeStore(appAPI, gate: gate)
        let external = Task { await gate.submit("Reject", to: "q1", via: externalAPI) }
        await waitUntil { store.replying["q1"] != nil }
        XCTAssertEqual(store.replying["q1"], "Reject", "an action reply disables the in-app buttons")

        let done = Finished()
        let inApp = Task { () -> ReplyResult in
            defer { done.value = true }
            return await store.reply("Approve", to: "q1")
        }
        await waitUntil { done.value || !appAPI.replies.isEmpty }
        appAPI.release()
        externalAPI.release()
        let inAppResult = await inApp.value
        let externalResult = await external.value

        XCTAssertEqual(inAppResult, .busy)
        XCTAssertEqual(externalResult, .accepted)
        XCTAssertEqual(appAPI.replies, [])
        XCTAssertEqual(externalAPI.replies, ["Reject"])
        XCTAssertNil(store.replying["q1"])
    }

    func testIndependentDecisionsAreAdmittedTogether() async {
        let api = HeldReplyAPI()
        let store = makeStore(api)
        let first = Task { await store.reply("Approve", to: "q1") }
        let second = Task { await store.reply("Hold", to: "q2") }
        await waitUntil { api.replies.count == 2 }
        XCTAssertEqual(store.replying, ["q1": "Approve", "q2": "Hold"])
        api.release()
        let results = [await first.value, await second.value]
        XCTAssertEqual(results, [.sent, .sent])
        XCTAssertTrue(store.replying.isEmpty)
    }

    func testFailureReleasesTheDecisionForARetry() async {
        let api = HeldReplyAPI()
        let store = makeStore(api)
        let failing = Task { await store.reply("Approve", to: "q1") }
        await waitUntil { store.replying["q1"] != nil }
        api.release(.failure(URLError(.timedOut)))
        let failed = await failing.value
        XCTAssertEqual(failed, .failed)
        XCTAssertNil(store.replying["q1"], "a failure frees the buttons")

        let retry = Task { await store.reply("Approve", to: "q1") }
        await waitUntil { api.replies.count == 2 }
        api.release()
        let retried = await retry.value
        XCTAssertEqual(retried, .sent, "the retry is admitted")
    }

    func testCancellationReleasesTheDecision() async {
        let api = HeldReplyAPI()
        let store = makeStore(api)
        let task = Task { await store.reply("Approve", to: "q1") }
        await waitUntil { store.replying["q1"] != nil }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, .failed)
        XCTAssertNil(store.replying["q1"], "a cancelled reply frees the buttons")
    }

    func testGateChangesRepublishTheStoreForEveryButtonSurface() async {
        let gate = DecisionReplyGate()
        let api = HeldReplyAPI()
        let store = makeStore(api, gate: gate)
        var changes = 0
        let observation = store.objectWillChange.sink { _ in changes += 1 }
        let task = Task { await gate.submit("Approve", to: "q1", via: api) }
        await waitUntil { changes > 0 }
        XCTAssertGreaterThan(changes, 0, "views observing the store re-render when a reply starts")
        api.release()
        _ = await task.value
        observation.cancel()
    }
}
