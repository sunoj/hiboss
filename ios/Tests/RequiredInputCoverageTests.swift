// Home coverage tests for stale fetches and reconnect reconciliation.
// Exports RequiredInputCoverageTests; depends on InboxStore and a controlled service.
// Verifies disconnected streams and old async results never authorize all-clear.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class RequiredInputCoverageTests: XCTestCase {
    func testStoppedStoreDiscardsLateRequiredInputFetch() async {
        let api = ControlledInputAPI()
        await api.holdNextFetch(returning: [Self.ask])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        let fetch = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        store.stop()
        await api.releaseFetch()
        await fetch.value
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertFalse(store.hasCompleteRequiredInputs)
    }

    func testOverlappingRefreshDiscardsOlderPendingSet() async {
        let api = ControlledInputAPI()
        await api.holdNextFetch(returning: [Self.ask])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        let oldFetch = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        await store.refreshRequiredInputs()
        await api.releaseFetch()
        await oldFetch.value
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertTrue(store.requiredInputLoaded)
    }

    func testPreReadyResolutionInvalidatesHeldSnapshot() async {
        let api = ControlledInputAPI()
        await api.holdNextFetch(returning: [Self.ask])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.requiredInputs = [Self.ask]
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.waitForStream(0)
        let oldFetch = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        await api.send(.resolved(Self.ask.id), to: 0)
        await eventually { store.requiredInputs.isEmpty }
        await api.releaseFetch()
        await oldFetch.value
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertFalse(store.hasCompleteRequiredInputs)
    }

    func testReconnectRequiresNewReadyAndCompleteFetch() async {
        let api = ControlledInputAPI()
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await eventually { store.hasCompleteRequiredInputs }
        await api.disconnect(0)
        await api.waitForStream(1)
        XCTAssertFalse(store.hasCompleteRequiredInputs)
        await api.setResponse([Self.ask])
        await api.sendReady(to: 1)
        await eventually {
            store.hasCompleteRequiredInputs && store.requiredInputs.map(\.id) == [Self.ask.id]
        }
    }

    func testFailureAfterSuccessfulEmptySnapshotDoesNotClaimAllClear() async {
        let api = ControlledInputAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await eventually { store.hasCompleteRequiredInputs }
        XCTAssertTrue(store.requiredInputs.isEmpty)
        await api.failNextFetch()
        await store.refreshRequiredInputs()
        XCTAssertFalse(store.hasCompleteRequiredInputs)
        XCTAssertNotNil(store.requiredInputError)
        XCTAssertTrue(store.requiredInputs.isEmpty)
    }

    func testLiveTextAppearsAndResolvesWithoutWaitingForReconciliation() async {
        let api = ControlledInputAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await eventually { store.hasCompleteRequiredInputs }
        await api.holdNextFetch(returning: [Self.ask])
        let refresh = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        await api.send(.message(Self.ask), to: 0)
        await eventually { store.requiredInputs.map(\.id) == [Self.ask.id] }
        XCTAssertEqual(store.requiredInputs.map(\.id), [Self.ask.id])
        XCTAssertTrue(store.hasCompleteRequiredInputs)
        XCTAssertEqual(store.answerability(for: Self.ask.id), .open)
        await api.releaseFetch()
        await refresh.value
        await eventually { store.hasCompleteRequiredInputs }
        await api.holdNextFetch(returning: [])
        let resolutionRefresh = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        await api.send(.resolved(Self.ask.id), to: 0)
        await eventually { store.requiredInputs.isEmpty }
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertTrue(store.hasCompleteRequiredInputs)
        XCTAssertEqual(store.answerability(for: Self.ask.id), .closed)
        await api.releaseFetch()
        await resolutionRefresh.value
        await eventually { store.hasCompleteRequiredInputs }
    }

    func testDisconnectInvalidatesHeldStreamReconciliation() async {
        let api = ControlledInputAPI()
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await eventually { store.hasCompleteRequiredInputs }
        await api.holdNextFetch(returning: [])
        let refresh = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        await api.send(.message(Self.ask), to: 0)
        await eventually { store.requiredInputs.map(\.id) == [Self.ask.id] }
        let staleFetch = refresh
        await api.disconnect(0)
        await api.waitForStream(1)
        await api.releaseFetch()
        await staleFetch.value
        XCTAssertFalse(store.hasCompleteRequiredInputs)
        XCTAssertEqual(store.requiredInputs.map(\.id), [Self.ask.id])
    }

    func testReplyKeepsInputCountedUntilTheServerResponds() async {
        for outcome in [ReplyOutcome.accepted, .alreadyResolved] {
            let api = ControlledInputAPI()
            await api.setResponse([Self.ask])
            let store = InboxStore(decisionAlertsEnabled: false)
            store.api = api
            store.startRequiredInputs(api)
            await api.sendReady(to: 0)
            await eventually { store.hasCompleteRequiredInputs }
            let reply = Task { await store.reply("Proceed", to: Self.ask.id) }
            await api.waitForHeldReply()
            XCTAssertFalse(store.withdrawn.contains(Self.ask.id))
            XCTAssertEqual(HomeAttentionSnapshot(messages: store.requiredInputs, withdrawn: store.withdrawn,
                                                 questionnaires: []).count, 1)
            await api.releaseReply(outcome)
            let result = await reply.value
            XCTAssertEqual(result, outcome == .accepted ? .sent : .alreadyResolved)
            XCTAssertEqual(HomeAttentionSnapshot(messages: store.requiredInputs, withdrawn: store.withdrawn,
                                                 questionnaires: []).count, 0)
            store.stop()
        }
    }

    func testStoppedStoreIgnoresALateAcceptedReply() async {
        let api = ControlledInputAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.requiredInputs = [Self.ask]
        store.requiredInputLoaded = true
        store.requiredInputReady = true
        let reply = Task { await store.reply("Proceed", to: Self.ask.id) }
        await eventually { await api.replyAttempts == 1 }
        store.stop()
        await api.releaseReply(.accepted)
        let result = await reply.value
        XCTAssertEqual(result, .sent)
        XCTAssertTrue(store.withdrawn.isEmpty)
        XCTAssertTrue(store.settledIDs.isEmpty)
        XCTAssertFalse(store.hasCompleteRequiredInputs)
    }

    private func eventually(_ condition: @escaping @MainActor () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected asynchronous state was not reached")
    }

    private static let ask = HistoryMessage(
        id: "stale", body: "Choose?", direction: "agent_to_boss", status: "sent",
        priority: "low", mode: "blocking", createdAt: "2026-09-23T00:00:00Z"
    )
}
