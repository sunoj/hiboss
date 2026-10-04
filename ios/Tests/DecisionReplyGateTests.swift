// One reply per decision in flight, whichever surface sends it: Home, detail, transcript,
// notification actions and Live Activity intents all pass DecisionReplyGate.
// Exports: DecisionReplyGateTests. Dependencies: XCTest, HiBoss app target, HeldReplyAPI, Pending.

import Combine
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionReplyGateTests: XCTestCase {
    private func makeStore(_ api: HeldReplyAPI, gate: DecisionReplyGate = DecisionReplyGate()) -> InboxStore {
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false, replyGate: gate)
        store.start(api: api)
        return store
    }

    // Every test releases only after the fake has recorded the reply, and awaits through
    // `Pending.settled()`, so a missing guard or a lost release fails rather than hangs.

    func testSecondTapWhileReplyIsInFlightSendsNothing() async throws {
        let api = HeldReplyAPI()
        let store = makeStore(api)
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
        let store = makeStore(api)
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
        let store = makeStore(api)
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
        let store = makeStore(api)
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
        let store = makeStore(api)
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
        let store = makeStore(api, gate: gate)
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
