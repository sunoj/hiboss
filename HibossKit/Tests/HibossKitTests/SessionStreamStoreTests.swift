// Session stream store tests: scroll lock, append, and resync reload.
// Exports: SessionStreamStoreTests.
// Dependencies: XCTest and HibossKit SessionStreamStore.

import XCTest
@testable import HibossKit

@MainActor
final class SessionStreamStoreTests: XCTestCase {
    func testScrollLockHoldsWhileEventsArrive() async {
        let api = MockSessionStreamAPI(events: [
            Self.event(sequence: 1, body: "one"),
            Self.event(sequence: 2, body: "two"),
        ])
        let store = SessionStreamStore(
            sessionID: "sess-1",
            pageSize: 50,
            maxWindow: 50,
            batchMilliseconds: 1,
            reconnectDelay: .milliseconds(10)
        )
        store.start(api: api)
        await waitUntil { !store.events.isEmpty }

        XCTAssertTrue(store.isFollowingLive)
        store.readerScrolledAway()
        XCTAssertFalse(store.isFollowingLive)

        store.applyStreamEventsForTesting([
            Self.event(sequence: 3, body: "three"),
            Self.event(sequence: 4, body: "four"),
        ])

        XCTAssertFalse(store.isFollowingLive, "live append must not re-enable follow")
        XCTAssertEqual(store.pendingWhileLocked, 2)
        XCTAssertEqual(store.events.map(\.sequence), [1, 2, 3, 4])

        store.jumpToLive()
        XCTAssertTrue(store.isFollowingLive)
        XCTAssertEqual(store.pendingWhileLocked, 0)
    }

    func testAppendDoesNotRefetchHistory() async {
        let api = MockSessionStreamAPI(events: [Self.event(sequence: 1, body: "seed")])
        let store = SessionStreamStore(
            sessionID: "sess-1", batchMilliseconds: 1, reconnectDelay: .milliseconds(10)
        )
        store.start(api: api)
        await waitUntil { store.events.count == 1 }
        let fetchesBefore = api.fetchCount

        store.applyStreamEventsForTesting([Self.event(sequence: 2, body: "live")])
        XCTAssertEqual(store.events.count, 2)
        XCTAssertEqual(api.fetchCount, fetchesBefore)
    }

    func testUnknownKindIsKept() async {
        let api = MockSessionStreamAPI(events: [
            SessionEvent(
                id: "e-x", sessionId: "sess-1", sequence: 1, kind: "future_kind",
                payload: .object(["note": .string("keep me")]),
                createdAt: "2026-08-14T09:00:00.000Z"
            ),
        ])
        let store = SessionStreamStore(sessionID: "sess-1", batchMilliseconds: 1)
        store.start(api: api)
        await waitUntil { !store.events.isEmpty }
        XCTAssertEqual(store.events.first?.kind, "future_kind")
        XCTAssertEqual(store.events.first?.displayBody, "future_kind")
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition not met before timeout")
    }

    private static func event(sequence: Int, body: String) -> SessionEvent {
        SessionEvent(
            id: "e\(sequence)",
            sessionId: "sess-1",
            sequence: sequence,
            kind: "message",
            direction: "agent_to_boss",
            actorName: "worker",
            payload: .object(["body": .string(body)]),
            createdAt: "2026-08-14T09:00:0\(sequence).000Z"
        )
    }
}

private final class MockSessionStreamAPI: SessionStreamServing, @unchecked Sendable {
    let events: [SessionEvent]
    private(set) var fetchCount = 0

    init(events: [SessionEvent]) { self.events = events }

    func fetchSessionEvents(
        sessionID _: String,
        after: Int?,
        limit: Int
    ) async throws -> SessionEventsPage {
        fetchCount += 1
        let start = (after ?? -1) + 1
        let slice = Array(events.filter { $0.sequence >= start }.prefix(limit))
        return SessionEventsPage(events: slice, nextAfter: slice.last?.sequence, resync: false)
    }

    func sessionEventStream(
        sessionID _: String,
        after _: Int
    ) async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}
