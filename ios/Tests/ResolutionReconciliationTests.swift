// Launch/foreground reconciliation: a required-input read retracts notifications of closed asks.
// Exports: ResolutionReconciliationTests.
// Dependencies: XCTest, HibossKit, InboxStore, ControlledInputAPI, FakeNotificationCenter.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class ResolutionReconciliationTests: XCTestCase {
    func testRequiredInputReadRetractsOnlyClosedAsks() async {
        let api = ControlledInputAPI()
        await api.setResponse([Self.ask("open")])
        let center = FakeNotificationCenter(records: [
            Self.record("n-open", id: "open", category: "HIBOSS_OPTIONS"),
            Self.record("n-closed", id: "closed", category: "HIBOSS_OPTIONS"),
            Self.record("n-text", id: "text", category: "HIBOSS_MESSAGE"),
            Self.record("n-note", id: "note", category: "HIBOSS_MESSAGE"),
            Self.record("n-new", id: "new", category: "HIBOSS_OPTIONS", date: .distantFuture),
            Self.record("n-system", id: nil, category: nil),
        ])
        let store = InboxStore(decisionAlertsEnabled: false, decisionActivitySync: { _, _ in })
        store.deliveredNotifications = center
        store.history = [Self.ask("text", status: "replied", options: []), Self.ask("note", status: "read")]
        store.api = api

        await store.refreshRequiredInputs()

        XCTAssertEqual(store.requiredInputs.map(\.id), ["open"])
        XCTAssertEqual(Set(center.removed), ["n-closed", "n-text"])
    }

    func testFailedReadRetractsNothing() async {
        let api = ControlledInputAPI()
        await api.failNextFetch()
        let center = FakeNotificationCenter(records: [Self.record("n", id: "closed", category: "HIBOSS_OPTIONS")])
        let store = InboxStore(decisionAlertsEnabled: false, decisionActivitySync: { _, _ in })
        store.deliveredNotifications = center
        store.api = api

        await store.refreshRequiredInputs()

        XCTAssertEqual(center.removed, [])
    }

    func testResolutionMarksTheAskClosed() {
        let store = InboxStore(decisionAlertsEnabled: false, decisionActivitySync: { _, _ in })
        store.requiredInputs = [Self.ask("open"), Self.ask("other")]
        store.requiredInputLoaded = true
        store.applyResolution("open")
        XCTAssertEqual(store.pending.map(\.id), ["other"])
    }

    private static func record(_ identifier: String, id: String?, category: String?,
                               date: Date = .distantPast) -> DeliveredNotificationRecord {
        DeliveredNotificationRecord(identifier: identifier, date: date, messageID: id, category: category)
    }

    private static func ask(_ id: String, status: String = "delivered", options: [String] = ["Ship", "Hold"])
        -> HistoryMessage
    {
        HistoryMessage(
            id: MessageID(rawValue: id), body: "Ship it?", agentName: "agent",
            direction: "agent_to_boss", status: status, priority: "high",
            channel: "api", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(options: options),
            createdAt: "2026-08-14T10:00:00Z", sessionId: "sess-a", sessionLabel: "feat"
        )
    }
}
