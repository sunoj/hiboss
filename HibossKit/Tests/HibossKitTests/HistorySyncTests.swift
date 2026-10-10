// Covers incremental replacement, trimming, opaque cursors, and coalescing barriers.
// Exports HistorySyncTests; observations model the arrays assigned by native stores.
// Depends on XCTest and the deterministic HistoryTestAPI.

import XCTest
@testable import HibossKit

@MainActor
final class HistorySyncTests: XCTestCase {
    func testMergeReplacesByIDSortsByCreatedDateAndTrims() async {
        let api = HistoryTestAPI([
            HistoryResponse(messages: [historyRow("old"), historyRow("changed", day: 2)],
                            total: 2, cursor: "opaque cursor +00:00"),
            HistoryResponse(
                messages: [historyRow("new", day: 3), historyRow("changed", day: 2, body: "edit")],
                total: 3, cursor: "next"
            ),
        ])
        let recorder = HistoryRecorder()
        let sync = HistorySync(api: api, limit: 2) { recorder.receive($0, $1) }
        await sync.synchronize()
        await sync.synchronize()
        XCTAssertEqual(recorder.publications.last?.map(\.id), ["new", "changed"])
        XCTAssertEqual(recorder.publications.last?.last?.body, "edit")
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, "opaque cursor +00:00"])
        await sync.stop()
    }

    func testIdenticalAndEmptyInclusiveDeltasDoNotRepublish() async {
        let row = historyRow("one")
        let api = HistoryTestAPI([
            HistoryResponse(messages: [row], total: 1, cursor: "1"),
            HistoryResponse(messages: [row], total: 1, cursor: "2"),
            HistoryResponse(messages: [], total: 1, cursor: "3"),
        ])
        let recorder = HistoryRecorder()
        let sync = HistorySync(api: api) { recorder.receive($0, $1) }
        for _ in 0..<3 { await sync.synchronize() }
        XCTAssertEqual(recorder.publications, [[row]])
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, "1", "2"])
        await sync.stop()
    }

    func testOldServerReplacesInsteadOfMergingAndResetsCursor() async {
        let api = HistoryTestAPI([
            HistoryResponse(messages: [historyRow("old")], total: 1, cursor: "1"),
            HistoryResponse(messages: [historyRow("replacement")], total: 1),
            HistoryResponse(messages: [], total: 0),
        ])
        let recorder = HistoryRecorder()
        let sync = HistorySync(api: api) { recorder.receive($0, $1) }
        await sync.synchronize()
        await sync.synchronize()
        XCTAssertEqual(recorder.publications.last?.map(\.id), ["replacement"])
        await sync.synchronize()
        XCTAssertEqual(recorder.publications.last, [])
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, "1", nil])
        await sync.stop()
    }

    func testHasMoreDiscardsPartialDeltaAndRefetchesFullPage() async {
        let full = historyRow("full")
        let api = HistoryTestAPI([
            HistoryResponse(messages: [historyRow("old")], total: 1, cursor: "1"),
            HistoryResponse(messages: [historyRow("partial")], total: 3, cursor: "2", hasMore: true),
            HistoryResponse(messages: [full], total: 3, cursor: "3", hasMore: true),
        ])
        let recorder = HistoryRecorder()
        let sync = HistorySync(api: api) { recorder.receive($0, $1) }
        await sync.synchronize()
        await sync.synchronize()
        XCTAssertEqual(recorder.publications.last, [full])
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, "1", nil])
        await sync.stop()
    }

    func testBurstCostsOneRequestAndInFlightBurstCostsOneTrailingRequest() async {
        let api = HistoryTestAPI([HistoryResponse(messages: [historyRow("one")], total: 1, cursor: "1")])
        let sync = HistorySync(api: api, debounce: .milliseconds(50)) { _, _ in }
        for _ in 0..<50 { await sync.request() }
        await sync.synchronize()
        var cursors = await api.cursors
        XCTAssertEqual(cursors.count, 1)
        await api.blockNext()
        await sync.request(debounced: false)
        await api.waitForRequests(2)
        for _ in 0..<50 { await sync.request() }
        await api.release()
        await sync.synchronize()
        cursors = await api.cursors
        XCTAssertEqual(cursors.count, 3)
        await sync.stop()
    }

    func testExplicitRefreshIgnoresCursor() async {
        let api = HistoryTestAPI([HistoryResponse(messages: [], total: 0, cursor: "1")])
        let sync = HistorySync(api: api, fullInterval: 900) { _, _ in }
        await sync.synchronize()
        await sync.synchronize(forceFull: true)
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, nil])
        await sync.stop()
    }
    func testExpiredPersistedFullFetchForcesFullReconciliation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = ConnectionConfig(serverURL: URL(string: "https://expired.test")!, bossToken: "synthetic")
        let cache = HistoryCache(directory: directory)
        let snapshot = HistorySnapshot(messages: [historyRow("expired")], cursor: "old",
                                       fullFetchedAt: Date(timeIntervalSinceNow: -901))
        try await cache.save(snapshot, bossID: "boss", key: HistoryCacheKey(config: config), epoch: 0)
        let api = HistoryTestAPI([HistoryResponse(messages: [], total: 0, cursor: "new")], config: config)
        let recorder = HistoryRecorder()
        let sync = HistorySync(api: api, cache: cache) { recorder.receive($0, $1) }
        await sync.synchronize()
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil])
        XCTAssertEqual(recorder.publications.last, [])
        await sync.stop()
    }

    func testPeriodicFullReconciliationRunsWithoutStreamEvents() async {
        let api = HistoryTestAPI([HistoryResponse(messages: [], total: 0, cursor: "1")])
        let sync = HistorySync(api: api, fullInterval: 0.03) { _, _ in }
        await sync.synchronize()
        await api.waitForRequests(2)
        await sync.stop()
        let cursors = await api.cursors
        XCTAssertEqual(Array(cursors.prefix(2)), [nil, nil])
    }

    func testStoppedSyncDoesNotPublishAnOutstandingResponse() async {
        let api = HistoryTestAPI([HistoryResponse(messages: [historyRow("one")], total: 1, cursor: "1")])
        let recorder = HistoryRecorder()
        let sync = HistorySync(api: api) { recorder.receive($0, $1) }
        await api.blockNext()
        let fetch = Task { await sync.synchronize() }
        await api.waitForRequests(1)
        await sync.stop()
        await api.release()
        await fetch.value
        XCTAssertTrue(recorder.publications.isEmpty)
    }

}
