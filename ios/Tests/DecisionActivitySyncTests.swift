// Live Activity lifecycle regression tests across input-loading gaps.
// Exports DecisionActivitySyncTests with a fake activity sink.
// Dependencies: InboxStore, ControlledInputAPI, Combine, and XCTest.

import Combine
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class DecisionActivitySyncTests: XCTestCase {
    func testColdLaunchPreservesActivityUntilRequiredInputsLoad() async {
        let api = ControlledInputAPI()
        await api.holdNextFetch(returning: [Self.ask])
        let sink = ActivitySink(running: Self.ask.id)
        let store = InboxStore(decisionActivitySync: sink.sync)
        store.start(api: api)
        defer { store.stop() }
        await api.waitForHeldFetch()
        await waitFor(store.$didLoad)

        XCTAssertFalse(store.requiredInputLoaded)
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertEqual(sink.running, Self.ask.id, "history must not end the existing activity during loading")
        XCTAssertEqual(sink.syncCount, 0, "history must wait for authoritative required inputs")
        await api.releaseFetch()
        await waitFor(store.$requiredInputLoaded)
        XCTAssertEqual(sink.running, Self.ask.id)
        XCTAssertEqual(sink.endCount, 0)
        XCTAssertEqual(sink.requestCount, 0)
    }

    func testConfigRestartPreservesActivityUntilNewInputsLoad() async {
        let sink = ActivitySink(running: Self.ask.id)
        let store = InboxStore(decisionActivitySync: sink.sync)
        let original = ControlledInputAPI()
        await original.setResponse([Self.ask])
        store.start(api: original)
        defer { store.stop() }
        await waitFor(store.$requiredInputLoaded)
        let syncCount = sink.syncCount

        let replacement = ControlledInputAPI()
        await replacement.holdNextFetch(returning: [Self.ask])
        store.start(api: replacement)
        await replacement.waitForHeldFetch()
        await waitFor(store.$didLoad)
        XCTAssertFalse(store.requiredInputLoaded)
        XCTAssertEqual(sink.syncCount, syncCount, "a config restart must not sync its cleared cache")
        XCTAssertEqual(sink.running, Self.ask.id)
        await replacement.releaseFetch()
        await waitFor(store.$requiredInputLoaded)
        XCTAssertEqual(sink.endCount, 0)
        XCTAssertEqual(sink.requestCount, 0)
    }

    func testReconnectWaitsForReadyFetchThenEndsOnEmptyServerAnswer() async {
        let api = ControlledInputAPI()
        await api.setResponse([Self.ask])
        let sink = ActivitySink(running: Self.ask.id)
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionActivitySync: sink.sync)
        store.start(api: api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await waitFor(store.$requiredInputLoaded)
        await api.disconnect(0)
        await api.waitForStream(1)
        let syncCount = sink.syncCount
        XCTAssertFalse(store.requiredInputLoaded)
        await store.syncDecisionActivity()
        XCTAssertEqual(sink.syncCount, syncCount, "disconnected inputs must not sync")

        await api.holdNextFetch(returning: [])
        await api.sendReady(to: 1)
        await api.waitForHeldFetch()
        await store.syncDecisionActivity()
        XCTAssertEqual(sink.syncCount, syncCount, "ready must wait for its reconciliation fetch")
        XCTAssertEqual(sink.running, Self.ask.id)
        await api.releaseFetch()
        await waitFor(store.$requiredInputLoaded)
        XCTAssertTrue(store.requiredInputs.isEmpty)
        XCTAssertNil(sink.running, "an authoritative empty server answer must end the activity")
        XCTAssertEqual(sink.endCount, 1)
        XCTAssertEqual(sink.requestCount, 0)
    }

    func testAlertPreferenceChangeWaitsForLoadedInputs() async {
        let api = ControlledInputAPI()
        await api.holdNextFetch(returning: [Self.ask])
        let sink = ActivitySink(running: Self.ask.id)
        let store = InboxStore(decisionActivitySync: sink.sync)
        store.api = api
        defer { store.stop() }
        let fetch = Task { await store.refreshRequiredInputs() }
        await api.waitForHeldFetch()
        store.setDecisionAlertsEnabled(false)
        await store.syncDecisionActivity()
        XCTAssertEqual(sink.syncCount, 0, "preference sync must also wait for authoritative inputs")
        await api.releaseFetch()
        await fetch.value
        XCTAssertNil(sink.running)
        XCTAssertEqual(sink.endCount, 1)
        XCTAssertEqual(sink.requestCount, 0)
        store.setDecisionAlertsEnabled(true)
        await waitFor(store.$requiredInputLoaded)
        await store.syncDecisionActivity()
        XCTAssertEqual(sink.running, Self.ask.id)
        XCTAssertEqual(sink.requestCount, 1)
    }

    private func waitFor(_ publisher: Published<Bool>.Publisher) async {
        let loaded = expectation(description: "store snapshot loaded")
        let observation = publisher.filter { $0 }.prefix(1).sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 3)
        withExtendedLifetime(observation) {}
    }

    private static let ask = HistoryMessage(
        id: "live", body: "Ship?", direction: "agent_to_boss", status: "sent",
        priority: "high", mode: "blocking", metadata: MessageMetadata(options: ["Ship", "Hold"]),
        createdAt: "2026-10-07T00:00:00Z"
    )
}

@MainActor
private final class ActivitySink {
    private(set) var running: MessageID?
    private(set) var syncCount = 0
    private(set) var endCount = 0
    private(set) var requestCount = 0

    init(running: MessageID) { self.running = running }

    func sync(_ candidates: [HistoryMessage], _ alertsEnabled: Bool) async {
        syncCount += 1
        let top = alertsEnabled ? DecisionActivityManager.rankedMessages(from: candidates).first?.id : nil
        if running != top {
            if running != nil { endCount += 1 }
            if top != nil { requestCount += 1 }
            running = top
        }
    }
}
