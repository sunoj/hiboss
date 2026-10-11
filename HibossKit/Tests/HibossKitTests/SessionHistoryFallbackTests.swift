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
        store.resumeFromForeground()
        for _ in 0..<20 { await Task.yield() }
        let after = await api.counts
        XCTAssertEqual(after.fetch, before.fetch)
        XCTAssertEqual(after.stream, before.stream)
        store.stop()
        observation.cancel()
    }
}

private actor UnavailableSessionAPI: SessionStreamServing {
    let failure: HibossAPIError
    let streamFails: Bool
    private(set) var counts = (fetch: 0, stream: 0)

    init(failure: HibossAPIError, streamFails: Bool = false) {
        self.failure = failure
        self.streamFails = streamFails
    }

    func fetchSessionEvents(sessionID: String, after: Int?, limit: Int) async throws -> SessionEventsPage {
        counts.fetch += 1
        if !streamFails { throw failure }
        return SessionEventsPage(events: [])
    }

    func sessionEventStream(
        sessionID: String, after: Int
    ) async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        counts.stream += 1
        return AsyncThrowingStream { $0.finish(throwing: failure) }
    }
}
