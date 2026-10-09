// Regression coverage for decision authorization while required inputs are refetched.
// Exports DecisionRefreshTests; uses InboxStore and the held ControlledInputAPI fixture.
// A loaded list remains authoritative until a coverage failure or account reset.

import Combine
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionRefreshTests: XCTestCase {
    func testRefreshKeepsOpenDecisionAnswerableDuringHeldRefetch() async {
        let (store, api) = await loadedStore()
        defer { store.stop() }
        var states: [DecisionAnswerability] = []
        let observation = store.$requiredInputLoaded.sink { loaded in
            states.append(DecisionAnswerability(id: Self.ask.id, openIDs: [Self.ask.id], loaded: loaded))
        }
        await api.holdNextFetch(returning: [Self.ask, Self.other])
        let refresh = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        assertOpen(store)
        XCTAssertTrue(store.requiredInputRefreshing)
        await api.releaseFetch()
        await refresh.value
        assertOpen(store)
        XCTAssertFalse(store.requiredInputRefreshing)
        XCTAssertTrue(states.allSatisfy { $0 == .open }, "refresh never invalidates loaded authorization")
        withExtendedLifetime(observation) {}
    }

    func testResolutionKeepsOtherDecisionAnswerableDuringHeldRefetch() async {
        let (store, api) = await loadedStore()
        defer { store.stop() }
        await api.holdNextFetch(returning: [Self.ask])
        await api.send(.resolved(Self.other.id), to: 0)
        await api.waitForHeldFetch()
        assertOpen(store)
        XCTAssertEqual(store.answerability(for: Self.other.id), .closed)
        let reconciliation = store.requiredFetchTask
        await api.releaseFetch()
        await reconciliation?.value
        assertOpen(store)
        XCTAssertEqual(store.answerability(for: Self.other.id), .closed)
    }

    func testReconnectKeepsOpenDecisionAnswerableBeforeReadyAndDuringHeldRefetch() async {
        let (store, api) = await loadedStore()
        defer { store.stop() }
        await api.disconnect(0)
        await api.waitForStream(1)
        assertOpen(store)
        XCTAssertFalse(store.requiredInputReady)
        await api.holdNextFetch(returning: [Self.ask, Self.other])
        await api.sendReady(to: 1)
        await api.waitForHeldFetch()
        assertOpen(store)
        let reconciliation = store.requiredFetchTask
        await api.releaseFetch()
        await reconciliation?.value
        assertOpen(store)
        XCTAssertTrue(store.hasCompleteRequiredInputs)
    }

    func testCoverageFailureDisablesLoadedDecisionUntilRecovery() async {
        let (store, api) = await loadedStore()
        defer { store.stop() }
        await api.failNextFetch()
        await store.refreshRequiredInputs()
        XCTAssertEqual(store.answerability(for: Self.ask.id), .checking)
        XCTAssertEqual(store.requiredInputs.map(\.id), [Self.ask.id, Self.other.id])
        await api.holdNextFetch(returning: [Self.ask, Self.other])
        let recovery = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        XCTAssertEqual(store.answerability(for: Self.ask.id), .checking)
        await api.releaseFetch()
        await recovery.value
        assertOpen(store)
        XCTAssertNil(store.requiredInputError)
    }

    func testAccountSwitchRequiresFirstLoadAgain() async {
        let (store, _) = await loadedStore()
        let nextAccount = ControlledInputAPI()
        await nextAccount.holdNextFetch(returning: [])
        store.start(api: nextAccount)
        defer { store.stop() }
        await nextAccount.waitForHeldFetch()
        XCTAssertFalse(store.requiredInputLoaded)
        XCTAssertEqual(store.answerability(for: Self.ask.id), .checking)
        XCTAssertTrue(store.requiredInputs.isEmpty)
        await nextAccount.releaseFetch()
        await waitUntil { store.requiredInputLoaded }
        XCTAssertEqual(store.answerability(for: Self.ask.id), .closed)
    }

    func testHeldRefreshCoverageTimeoutInvalidatesListUntilFetchRecovers() async {
        let (store, api) = await loadedStore()
        defer { store.stop() }
        await api.holdNextFetch(returning: [Self.ask, Self.other])
        let refresh = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        assertOpen(store)
        let failedCoverage = expectation(description: "refresh coverage timeout")
        let observation = store.$requiredInputLoaded.filter { !$0 }.prefix(1).sink { _ in
            failedCoverage.fulfill()
        }
        await fulfillment(of: [failedCoverage], timeout: 10)
        XCTAssertEqual(store.answerability(for: Self.ask.id), .checking)
        XCTAssertNotNil(store.requiredInputError)
        await api.releaseFetch()
        await refresh.value
        assertOpen(store)
        XCTAssertNil(store.requiredInputError)
        withExtendedLifetime(observation) {}
    }

    func testReconnectCoverageFailureNeedsReadyBeforeFetchRestoresAuthorization() async {
        let (store, api) = await loadedStore()
        defer { store.stop() }
        await api.disconnect(0)
        await api.waitForStream(1)
        assertOpen(store)
        let failedCoverage = expectation(description: "reconnect coverage timeout")
        let observation = store.$requiredInputLoaded.filter { !$0 }.prefix(1).sink { _ in
            failedCoverage.fulfill()
        }
        await fulfillment(of: [failedCoverage], timeout: 10)
        XCTAssertEqual(store.answerability(for: Self.ask.id), .checking)
        await store.refreshRequiredInputs()
        XCTAssertEqual(store.answerability(for: Self.ask.id), .checking)
        XCTAssertNotNil(store.requiredInputError)
        await api.sendReady(to: 1)
        await waitUntil { store.hasCompleteRequiredInputs }
        assertOpen(store)
        XCTAssertNil(store.requiredInputError)
        withExtendedLifetime(observation) {}
    }

    private func loadedStore() async -> (InboxStore, ControlledInputAPI) {
        let api = ControlledInputAPI()
        await api.setResponse([Self.ask, Self.other])
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.api = api
        store.history = [Self.ask, Self.other]
        store.startRequiredInputs(api)
        await api.sendReady(to: 0)
        await waitUntil { store.hasCompleteRequiredInputs }
        assertOpen(store)
        return (store, api)
    }

    private func assertOpen(_ store: InboxStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(store.requiredInputLoaded, file: file, line: line)
        XCTAssertEqual(store.answerability(for: Self.ask.id), .open, file: file, line: line)
        XCTAssertTrue(store.todaySnapshot(now: .now).decisions.contains { $0.id == Self.ask.id },
                      file: file, line: line)
        let events = DemoSessionStream.events(for: "session", from: [Self.ask])
        XCTAssertEqual(SessionReplyTarget.eligible(events: events, store: store).map(\.id),
                       [Self.ask.id], file: file, line: line)
    }

    private static let ask = HistoryMessage(
        id: "open", body: "Proceed?", direction: "agent_to_boss", status: "sent", priority: "high",
        mode: "blocking", metadata: MessageMetadata(options: ["Yes", "No"]),
        createdAt: "2026-10-10T00:00:00Z", sessionId: "session"
    )
    private static let other = HistoryMessage(
        id: "other", body: "Which dataset?", direction: "agent_to_boss", status: "sent", priority: "low",
        mode: "blocking", createdAt: "2026-10-10T00:00:00Z", sessionId: "session"
    )
}
