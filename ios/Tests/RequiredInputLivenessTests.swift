// Regression coverage for a connected inbox with an unhealthy required-input stream.
// Exports RequiredInputLivenessTests; verifies errors without authorizing all-clear.
// Dependencies: InboxStore, ControlledInputAPI, Combine and XCTest.

import Combine
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class RequiredInputLivenessTests: XCTestCase {
    func testSilentRequiredStreamEscalatesWhileMainStreamIsConnected() async {
        let api = ControlledInputAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: api)
        defer { store.stop() }
        await api.waitForStream(0)
        await wait(8.2)
        XCTAssertEqual(store.connectionState, .connected)
        XCTAssertFalse(store.hasCompleteRequiredInputs)
        XCTAssertNotNil(store.requiredInputError, "Missing ready must become an actionable source failure")
    }

    func testCleanRequiredStreamEndReconnectsWithoutAnImmediateError() async {
        let api = ControlledInputAPI()
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.start(api: api)
        defer { store.stop() }
        await api.sendReady(to: 0)
        await loaded(store)
        await api.disconnect(0)
        await api.waitForStream(1)
        XCTAssertEqual(store.connectionState, .connected)
        XCTAssertFalse(store.hasCompleteRequiredInputs)
        XCTAssertNil(store.requiredInputError, "a routine stream rotation is not a failure")
    }

    func testRoutineMessageStreamRotationStaysConnected() async {
        let api = ControlledInputAPI()
        await api.endMessageStreamsCleanly()
        let store = InboxStore(reconnectDelay: .milliseconds(10), decisionAlertsEnabled: false)
        store.start(api: api)
        defer { store.stop() }
        var states: [ConnectionState] = []
        for _ in 0..<25 {
            await wait(0.02)
            states.append(store.connectionState)
        }
        XCTAssertTrue(states.allSatisfy { $0 == .connected },
                      "a clean server rotation must not show a reconnect state: \(states)")
    }

    private func loaded(_ store: InboxStore) async {
        let loaded = expectation(description: "required-input snapshot")
        let observation = store.$requiredInputLoaded.filter { $0 }.prefix(1).sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 3)
        withExtendedLifetime(observation) {}
    }

    private func wait(_ seconds: TimeInterval) async {
        let elapsed = expectation(description: "coverage deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { elapsed.fulfill() }
        await fulfillment(of: [elapsed], timeout: seconds + 2)
    }
}
