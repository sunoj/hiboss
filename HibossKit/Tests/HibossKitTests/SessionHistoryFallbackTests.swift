// Verifies client-only sessions and unavailable endpoints select history without network errors.
// Exports SessionHistoryFallbackTests; the actor fixture records history and SSE requests.
// Dependencies: XCTest, Combine, and HibossKit's session stream boundary.

import Combine
import XCTest
@testable import HibossKit

@MainActor
final class SessionHistoryFallbackTests: XCTestCase {
    func testDirectNeverCallsSessionEndpoints() async {
        let api = UnavailableSessionAPI(failure: .requestFailed(status: 404, message: "gone"))
        let store = SessionStreamStore(sessionID: SessionGrouping.directSessionID)
        store.start(api: api)
        await store.refresh()
        store.resumeFromForeground()
        await store.loadEarlier()
        for _ in 0..<20 { await Task.yield() }
        let counts = await api.counts
        XCTAssertEqual(counts.fetch, 0)
        XCTAssertEqual(counts.stream, 0)
        XCTAssertTrue(store.usesHistory)
        XCTAssertNil(store.loadError)
        store.stop()
    }

    func testHistory404SelectsFallbackInsteadOfLoadError() async {
        await checkUnavailable(streamFails: false)
    }

    func testStream404SelectsFallbackAndStopsReconnecting() async {
        await checkUnavailable(streamFails: true)
    }

    func testHistory404CanRecoverLiveEventsOnRefresh() async {
        await checkRecovery(streamFails: false)
    }

    func testStream404CanRecoverLiveEventsOnRefresh() async {
        await checkRecovery(streamFails: true)
    }

    private func checkRecovery(streamFails: Bool) async {
        let api = UnavailableSessionAPI(failure: .requestFailed(status: 404, message: "not accessible"),
                                        streamFails: streamFails)
        let store = SessionStreamStore(sessionID: "session", batchMilliseconds: 1)
        let fallback = expectation(description: "History fallback")
        let observation = store.$usesHistory.filter { $0 }.prefix(1).sink { _ in fallback.fulfill() }
        store.start(api: api)
        await fulfillment(of: [fallback], timeout: 2)
        await api.makeAvailable()
        let streamed = expectation(description: "Recovered live event")
        let events = store.$events.filter { $0.last?.id == "live" }.prefix(1).sink { _ in streamed.fulfill() }
        await store.refresh()
        await fulfillment(of: [streamed], timeout: 2)
        XCTAssertFalse(store.usesHistory)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.connectionState, .connected)
        XCTAssertEqual(store.events.map(\.id), ["live"])
        let counts = await api.counts
        XCTAssertEqual(counts.fetch, 2)
        XCTAssertEqual(counts.stream, streamFails ? 2 : 1)
        store.stop()
        observation.cancel()
        events.cancel()
    }

    func testGenuineServerFailureRemainsLoadError() async {
        let api = UnavailableSessionAPI(failure: .requestFailed(status: 503, message: "offline"))
        let store = SessionStreamStore(sessionID: "ended")
        let completed = expectation(description: "Load completes")
        let observation = store.$loadError.dropFirst().compactMap { $0 }.prefix(1).sink { _ in
            completed.fulfill()
        }
        store.start(api: api)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertFalse(store.usesHistory)
        XCTAssertNotNil(store.loadError)
        store.stop()
        observation.cancel()
    }

    func testEmptyHistoryStreamFailureRetainsFailureUntilRetry() async {
        let api = UnavailableSessionAPI(failure: .requestFailed(status: 503, message: "offline"),
                                        streamFails: true)
        let store = SessionStreamStore(sessionID: "session", batchMilliseconds: 1,
                                       reconnectDelay: .seconds(60))
        let failed = expectation(description: "Empty transcript stream fails")
        let failure = store.$connectionState.filter {
            if case .failed = $0 { return true }
            return false
        }.prefix(1).sink { _ in failed.fulfill() }
        store.start(api: api)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertFalse(store.usesHistory)
        XCTAssertNil(store.loadError)
        XCTAssertNotNil(store.connectionState.detail, "Backoff must retain the failure for Retry")
        let before = await api.counts
        XCTAssertEqual(before.fetch, 1)
        XCTAssertEqual(before.stream, 1)
        await api.makeAvailable()
        let recovered = expectation(description: "Retry restores the stream")
        let events = store.$events.filter { $0.last?.id == "live" }.prefix(1).sink { _ in
            recovered.fulfill()
        }
        await store.refresh()
        await fulfillment(of: [recovered], timeout: 2)
        XCTAssertEqual(store.connectionState, .connected)
        XCTAssertNil(store.loadError)
        store.stop()
        failure.cancel()
        events.cancel()
    }

    private func checkUnavailable(streamFails: Bool) async {
        let api = UnavailableSessionAPI(failure: .requestFailed(status: 404, message: "gone"),
                                        streamFails: streamFails)
        let store = SessionStreamStore(sessionID: "ended")
        let completed = expectation(description: "Unavailable endpoint is classified")
        let observation = store.$usesHistory.combineLatest(store.$loadError, store.$connectionState)
            .filter { history, error, state in
            if history || error != nil { return true }
            if case .failed = state { return true }
            return false
        }.prefix(1).sink { _ in completed.fulfill() }
        store.start(api: api)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertTrue(store.usesHistory)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.connectionState, .disconnected)
        let before = await api.counts
        await store.refresh()
        let after = await api.counts
        XCTAssertEqual(after.fetch, before.fetch + 1)
        XCTAssertTrue(store.usesHistory)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.connectionState, .disconnected)
        store.resumeFromForeground()
        for _ in 0..<20 { await Task.yield() }
        let foreground = await api.counts
        XCTAssertEqual(foreground.fetch, after.fetch)
        XCTAssertEqual(foreground.stream, after.stream)
        store.stop()
        observation.cancel()
    }
}

private actor UnavailableSessionAPI: SessionStreamServing {
    let failure: HibossAPIError
    let streamFails: Bool
    private var available = false
    private(set) var counts = (fetch: 0, stream: 0)

    init(failure: HibossAPIError, streamFails: Bool = false) {
        self.failure = failure
        self.streamFails = streamFails
    }

    func fetchSessionEvents(sessionID: String, after: Int?, limit: Int) async throws -> SessionEventsPage {
        counts.fetch += 1
        if !available && (!streamFails || counts.fetch > 1) { throw failure }
        return SessionEventsPage(events: [])
    }

    func makeAvailable() { available = true }

    func sessionEventStream(
        sessionID: String, after: Int
    ) async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        counts.stream += 1
        if !available { return AsyncThrowingStream { $0.finish(throwing: failure) } }
        let event = SessionEvent(id: "live", sessionId: sessionID, sequence: 1, kind: "message",
                                 payload: .object(["body": .string("Live again")]), createdAt: "")
        return AsyncThrowingStream { $0.yield(.event(event)) }
    }
}
