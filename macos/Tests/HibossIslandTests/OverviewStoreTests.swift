// Verifies overview invalidation without a full-window polling clock.
// Exports: OverviewStoreTests for unchanged inputs, live updates, and deadline transitions.
// Dependencies: XCTest, HibossKit, OverviewStore, AttentionTestSupport.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class OverviewStoreTests: XCTestCase {
    func testUnchangedMessagesKeepSnapshotDuringClockAndInputUpdates() {
        let store = OverviewStore()
        let now = Date()
        let question = AttentionTestSupport.ask(id: "ask", options: ["Ship"], sessionStatus: "waiting")
        store.update(history: [question], live: nil, now: now)
        store.update(history: [question], live: nil, now: now.addingTimeInterval(1))
        XCTAssertEqual(store.snapshot.now, now)
        let resolved = AttentionTestSupport.ask(id: "ask", options: ["Ship"], status: "replied")
        store.update(history: [resolved], live: nil, now: now.addingTimeInterval(2))
        XCTAssertEqual(store.snapshot.count(.needsYou), 0)
        XCTAssertEqual(store.snapshot.count(.completed), 1)
    }

    func testLiveChangesInvalidateSnapshot() {
        let store = OverviewStore()
        let live = OptionMessage(id: "live", body: "Ship?", agentName: "Agent",
            metadata: MessageMetadata(options: ["Ship"], defaultOption: "Ship"),
            expiresAt: AttentionTestSupport.iso(Date().addingTimeInterval(60)))
        store.update(history: [], live: live, requiredInputs: [TodayProjection.historyMessage(from: live)])
        XCTAssertEqual(store.snapshot.count(.automatic), 1)
        store.update(history: [], live: nil)
        XCTAssertEqual(store.snapshot.count(.all), 0)
    }

    func testDeadlineUpdatesCountsWithoutNewServerMessages() async throws {
        let store = OverviewStore()
        let deadline = Date().addingTimeInterval(0.15)
        let question = AttentionTestSupport.ask(id: "timer", options: ["Ship"], defaultOption: "Ship",
            expiresAt: deadline.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        store.update(history: [question], live: nil, requiredInputs: [question])
        XCTAssertEqual(store.snapshot.count(.automatic), 1)
        for _ in 0..<100 {
            if store.snapshot.count(.automatic) == 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(store.snapshot.count(.automatic), 0)
        XCTAssertEqual(store.snapshot.count(.completed), 1)
        XCTAssertEqual(store.snapshot.count(.all), 1)
    }

    func testLateAnswerFromPreviousIdentityDoesNotRestoreHistory() async {
        let identity = AccountIdentityGeneration()
        let store = OverviewStore(identity: identity)
        let question = AttentionTestSupport.ask(id: "old", options: ["Ship"], sessionStatus: "waiting")
        store.update(history: [question], live: nil, requiredInputs: [question], requiredInputLoaded: true)
        let started = expectation(description: "reply started")
        var release: (() -> Void)?
        let task = Task {
            await store.answer("Ship", for: question.id, using: { _, _ in
                started.fulfill()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    release = { continuation.resume() }
                }
                return nil
            })
        }
        await fulfillment(of: [started])
        identity.changed()
        store.accountDidChange()
        release?()
        _ = await task.value

        XCTAssertTrue(store.snapshot.history.isEmpty)
        XCTAssertTrue(store.snapshot.today.decisions.isEmpty)
    }
}
