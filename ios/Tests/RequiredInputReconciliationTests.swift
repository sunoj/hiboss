// Regression coverage for authoritative snapshots concurrent with live input events.
// Exports RequiredInputReconciliationTests; uses the controlled inbox service.
// Dependencies: InboxStore, HibossKit, and XCTest.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class RequiredInputReconciliationTests: XCTestCase {
    func testLiveEventsDoNotRestartAHeldReadySnapshot() async {
        let api = ControlledInputAPI()
        let old = ask("old", body: "Old request")
        let update = ask("new", body: "Updated request")
        await api.holdNextFetch(returning: [old])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await api.waitForHeldFetch()
        let snapshot = store.requiredFetchTask
        await api.send(.message(update), to: 0)
        await api.send(.resolved(old.id), to: 0)
        await eventually { store.requiredInputs == [update] }
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 1, "Live events must let the complete snapshot finish on a slow link")
        await api.releaseFetch()
        await snapshot?.value
        await eventually { store.hasCompleteRequiredInputs }
        XCTAssertEqual(store.requiredInputs, [update], "Newer stream changes must survive the older snapshot")
    }

    func testDuplicateReadyDoesNotCancelTheCurrentSnapshot() async {
        let api = ControlledInputAPI()
        let request = ask("current", body: "Current request")
        await api.holdNextFetch(returning: [request])
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await api.waitForHeldFetch()
        let snapshot = store.requiredFetchTask
        await api.sendReady(to: 0)
        for _ in 0..<20 { await Task.yield() }
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 1)
        await api.releaseFetch()
        await snapshot?.value
        await eventually { store.hasCompleteRequiredInputs }
        XCTAssertEqual(store.requiredInputs, [request])
    }

    func testLiveEventsAfterCoverageDoNotFetchAnotherSnapshot() async {
        let api = ControlledInputAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await eventually { store.hasCompleteRequiredInputs }
        let request = ask("live", body: "Live request")
        await api.send(.message(request), to: 0)
        await eventually { store.requiredInputs == [request] }
        await api.send(.resolved(request.id), to: 0)
        await eventually { store.requiredInputs.isEmpty }
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(store.hasCompleteRequiredInputs)
    }

    func testFailedReadySnapshotRetriesWithoutAnotherStreamEvent() async {
        let api = ControlledInputAPI()
        let request = ask("retry", body: "Retried request")
        await api.setResponse([request])
        await api.failNextFetch()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await eventually { store.requiredInputError != nil }
        XCTAssertFalse(store.hasCompleteRequiredInputs)
        await eventually { store.hasCompleteRequiredInputs }
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(store.requiredInputs, [request])
        XCTAssertNil(store.requiredInputError)
    }

    func testStoppingCancelsAScheduledSnapshotRetry() async {
        let api = ControlledInputAPI()
        await api.failNextFetch()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.api = api
        store.startRequiredInputs(api)
        await api.sendReady(to: 0)
        await eventually { store.requiredInputError != nil }
        let retry = store.requiredRetryTask
        store.stop()
        await retry?.value
        let reads = await api.requiredFetchCount()
        XCTAssertEqual(reads, 1)
        XCTAssertFalse(store.hasCompleteRequiredInputs)
    }

    private func ask(_ id: MessageID, body: String) -> HistoryMessage {
        HistoryMessage(id: id, body: body, direction: "agent_to_boss", status: "sent",
                       priority: "low", mode: "blocking", createdAt: "2026-10-11T00:00:00Z")
    }

    private func eventually(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected asynchronous state was not reached")
    }
}
