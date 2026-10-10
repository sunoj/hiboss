// Verifies cached launch, identity isolation, and deletion rejecting stale writes.
// Exports HistoryCacheTests with temporary Application Support equivalents.
// Depends on XCTest, Foundation, and HistorySync test fixtures.

import XCTest
@testable import HibossKit

@MainActor
final class HistoryCacheTests: XCTestCase {
    func testDirectorySnapshotAndLookupAreExcludedFromBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HistoryCache(directory: directory)
        let config = ConnectionConfig(serverURL: URL(string: "https://history.test")!, bossToken: "synthetic")
        try await cache.save(HistorySnapshot(messages: [historyRow("one")]), bossID: "boss",
                             key: HistoryCacheKey(config: config), epoch: 0)
        let root = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).first)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        for url in [root] + files {
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            XCTAssertEqual(values.isExcludedFromBackup, true)
        }
    }

    func testRoundTripShowsCachedRowsBeforeNetworkCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HistoryCache(directory: directory)
        let config = ConnectionConfig(serverURL: URL(string: "https://history.test")!, bossToken: "synthetic")
        let key = HistoryCacheKey(config: config)
        let snapshot = HistorySnapshot(messages: [historyRow("cached")], cursor: "verbatim +01:00",
                                       fullFetchedAt: .now)
        try await cache.save(snapshot, bossID: "boss", key: key, epoch: 0)
        let loaded = try await cache.load(for: key)
        XCTAssertEqual(loaded?.0, "boss")
        XCTAssertEqual(loaded?.1, snapshot)
        let api = HistoryTestAPI([HistoryResponse(messages: [], total: 1, cursor: "next")], config: config)
        await api.blockNext()
        let recorder = HistoryRecorder()
        let sync = HistorySync(api: api, cache: cache) { recorder.receive($0, $1) }
        await sync.request(debounced: false)
        await api.waitForRequests(1)
        XCTAssertEqual(recorder.publications, [snapshot.messages])
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [snapshot.cursor])
        await api.release()
        await sync.synchronize()
        XCTAssertEqual(recorder.publications.count, 1)
        await sync.stop()
    }

    func testSignOutDeletionRejectsOutstandingWritesAndIsolatesServers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HistoryCache(directory: directory)
        let server = URL(string: "https://history.test")!
        let key = HistoryCacheKey(config: ConnectionConfig(serverURL: server, bossToken: "synthetic"))
        let otherKey = HistoryCacheKey(config: ConnectionConfig(
            serverURL: URL(string: "https://other.test")!, bossToken: "synthetic"
        ))
        let snapshot = HistorySnapshot(messages: [historyRow("one")], cursor: "cursor")
        try await cache.save(snapshot, bossID: "boss", key: key, epoch: 0)
        try await cache.save(snapshot, bossID: "boss", key: otherKey, epoch: 0)
        try await cache.delete(serverURL: server)
        try await cache.save(snapshot, bossID: "boss", key: key, epoch: 0)
        let deleted = try await cache.load(for: key)
        let other = try await cache.load(for: otherKey)
        XCTAssertNil(deleted)
        XCTAssertEqual(other?.1, snapshot)
    }

    func testTwoBossesAtOneServerDoNotShareRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HistoryCache(directory: directory)
        let server = URL(string: "https://history.test")!
        let first = HistoryCacheKey(config: ConnectionConfig(serverURL: server, bossToken: "synthetic-first"))
        let second = HistoryCacheKey(config: ConnectionConfig(
            serverURL: server, bossToken: "synthetic-second"
        ))
        try await cache.save(
            HistorySnapshot(messages: [historyRow("first")]), bossID: "first", key: first, epoch: 0
        )
        try await cache.save(
            HistorySnapshot(messages: [historyRow("second")]), bossID: "second", key: second, epoch: 0
        )
        let a = try await cache.load(for: first)
        let b = try await cache.load(for: second)
        XCTAssertEqual(a?.1.messages.first?.id, "first")
        XCTAssertEqual(b?.1.messages.first?.id, "second")
    }
}
