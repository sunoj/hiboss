// Transcript refresh regressions for superseded and stopped history requests.
// Exports TranscriptRefreshTests; prevents late reads replacing newer content or reopening streams.
// Dependencies: XCTest, HibossKit and a continuation-controlled SessionStreamServing fixture.

import HibossKit
import XCTest

@MainActor
final class TranscriptRefreshTests: XCTestCase {
    func testLateRefreshCannotReplaceNewerTranscript() async {
        let api = HeldTranscriptAPI()
        let store = SessionStreamStore(sessionID: "session")
        store.start(api: api)
        await api.waitForFetch(1)
        let newer = Task { await store.refresh() }
        await api.waitForFetch(2)
        await api.finish(2, body: "newer")
        await newer.value
        XCTAssertEqual(store.events.first?.displayBody, "newer")
        await api.finish(1, body: "older")
        await settled()
        XCTAssertEqual(store.events.first?.displayBody, "newer")
        XCTAssertFalse(store.isLoading)
        store.stop()
    }

    func testStoppedReadDoesNotStartAConnection() async {
        let api = HeldTranscriptAPI()
        let store = SessionStreamStore(sessionID: "session")
        store.start(api: api)
        await api.waitForFetch(1)
        store.stop()
        await api.finish(1, body: "late")
        await settled()
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.connectionState, .disconnected)
        XCTAssertFalse(store.isLoading)
    }

    func testLateBackfillCannotAppendToAReplacedWindow() async {
        let api = HeldTranscriptAPI()
        let store = SessionStreamStore(sessionID: "session")
        store.start(api: api)
        await api.waitForFetch(1)
        await api.finish(1, body: "seed", sequence: 10)
        await settled()
        let earlier = Task { await store.loadEarlier() }
        await api.waitForFetch(2)
        let refresh = Task { await store.refresh() }
        await api.waitForFetch(3)
        await api.finish(3, body: "new window", sequence: 12)
        await refresh.value
        await api.finish(2, body: "old window", sequence: 9)
        await earlier.value
        XCTAssertEqual(store.events.map(\.sequence), [12])
        XCTAssertFalse(store.isBackfilling)
        store.stop()
    }

    private func settled() async {
        let settled = expectation(description: "late read completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
    }
}

private actor HeldTranscriptAPI: SessionStreamServing {
    private var count = 0
    private var reads: [Int: CheckedContinuation<SessionEventsPage, Error>] = [:]
    private var waits: [Int: CheckedContinuation<Void, Never>] = [:]

    func fetchSessionEvents(sessionID: String, after: Int?, limit: Int) async throws -> SessionEventsPage {
        count += 1
        let number = count
        return try await withCheckedThrowingContinuation { continuation in
            reads[number] = continuation
            waits.removeValue(forKey: number)?.resume()
        }
    }

    func waitForFetch(_ number: Int) async {
        guard reads[number] == nil else { return }
        await withCheckedContinuation { waits[number] = $0 }
    }

    func finish(_ number: Int, body: String, sequence: Int? = nil) {
        let event = SessionEvent(id: "event-\(number)", sessionId: "session", sequence: sequence ?? number,
                                 kind: "message", payload: .object(["body": .string(body)]),
                                 createdAt: "2026-10-07T00:00:00Z")
        reads.removeValue(forKey: number)?.resume(returning: SessionEventsPage(events: [event]))
    }

    func sessionEventStream(sessionID: String, after: Int)
        async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        AsyncThrowingStream { _ in }
    }
}
