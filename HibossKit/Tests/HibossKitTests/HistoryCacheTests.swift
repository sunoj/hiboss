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
        _ = try await cache.load(for: HistoryCacheKey(config: config))
        try await cache.save(HistorySnapshot(messages: [historyRow("one")]), bossID: "boss",
                             key: HistoryCacheKey(config: config), epoch: 0)
        let root = directory.appendingPathComponent(HistoryCacheKey(config: config).server)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        for url in [directory, directory.appendingPathComponent("active-account"), root] + files {
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
        _ = try await cache.load(for: key)
        let snapshot = HistorySnapshot(messages: [historyRow("cached")], cursor: "verbatim +01:00",
                                       fullFetchedAt: .now)
        try await cache.save(snapshot, bossID: "boss", key: key, epoch: 0)
        let loaded = try await cache.load(for: key).cached
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
        _ = try await cache.load(for: key)
        try await cache.save(snapshot, bossID: "boss", key: key, epoch: 0)
        try await cache.delete(serverURL: server)
        try await cache.save(snapshot, bossID: "boss", key: key, epoch: 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        let deleted = try await cache.load(for: key)
        XCTAssertNil(deleted.cached)
        XCTAssertGreaterThan(deleted.epoch, 0)
        let otherEpoch = try await cache.load(for: otherKey).epoch
        try await cache.save(snapshot, bossID: "boss", key: otherKey, epoch: otherEpoch)
        try await cache.delete(serverURL: server)
        let other = try await cache.load(for: otherKey).cached
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
        _ = try await cache.load(for: first)
        try await cache.save(
            HistorySnapshot(messages: [historyRow("first")]), bossID: "first", key: first, epoch: 0
        )
        let a = try await cache.load(for: first).cached
        XCTAssertEqual(a?.1.messages.first?.id, "first")
        let switched = try await cache.load(for: second)
        XCTAssertNil(switched.cached)
        try await cache.save(
            HistorySnapshot(messages: [historyRow("second")]), bossID: "second", key: second,
            epoch: switched.epoch
        )
        let b = try await cache.load(for: second).cached
        XCTAssertEqual(b?.1.messages.first?.id, "second")
        let returning = try await cache.load(for: first).cached
        XCTAssertNil(returning)
    }

    func testSwitchWipesEveryOtherIdentityOnSameAndDifferentServers() async throws {
        for server in ["https://history.test", "https://other.test"] {
            let directory = temporaryDirectory()
            let cache = HistoryCache(directory: directory)
            let first = key()
            _ = try await seed(cache, key: first)
            let orphan = directory.appendingPathComponent(HistoryCacheKey.digest("orphan-server"))
            try FileManager.default.copyItem(at: directory.appendingPathComponent(first.server), to: orphan)
            let second = key(server: server, token: "synthetic-second")
            let switched = try await cache.load(for: second)
            XCTAssertNil(switched.cached)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                           ["active-account"])
            XCTAssertGreaterThan(switched.epoch, 0)
        }
    }

    func testStaleSaveCannotRecreateOldCacheOrOverwriteNewAccount() async throws {
        let directory = temporaryDirectory()
        let cache = HistoryCache(directory: directory)
        let first = key()
        let oldEpoch = try await seed(cache, key: first)
        let second = key(token: "synthetic-second")
        let newEpoch = try await seed(cache, key: second, row: "new")
        try await cache.save(HistorySnapshot(messages: [historyRow("stale")]), bossID: "boss",
                             key: first, epoch: oldEpoch)
        let current = try await cache.load(for: second).cached
        XCTAssertEqual(current?.1.messages.first?.id, "new")
        let lookup = directory.appendingPathComponent(first.server).appendingPathComponent(
            "lookup-" + first.credential
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: lookup.path))
        let returning = try await cache.load(for: first)
        XCTAssertGreaterThan(returning.epoch, oldEpoch)
        try await cache.save(HistorySnapshot(), bossID: "boss", key: first, epoch: oldEpoch)
        try await cache.save(HistorySnapshot(), bossID: "boss", key: second, epoch: newEpoch)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                       ["active-account"])
    }

    func testColdLaunchWithForeignMarkerWipesHistoryAndPersistsNewAccount() async throws {
        let directory = temporaryDirectory()
        _ = try await seed(HistoryCache(directory: directory), key: key())
        let second = key(server: "https://other.test", token: "synthetic-second")
        let relaunched = HistoryCache(directory: directory)
        _ = try await seed(relaunched, key: second, row: "new")
        let oldRoot = directory.appendingPathComponent(key().server)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldRoot.path))
        let restored = try await HistoryCache(directory: directory).load(for: second).cached
        XCTAssertEqual(restored?.1.messages.first?.id, "new")
        let marker = try String(
            contentsOf: directory.appendingPathComponent("active-account"), encoding: .utf8
        )
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: Data(marker.utf8)), second.account)
        XCTAssertFalse(marker.contains("synthetic"))
    }

    func testMissingMarkerWipesLegacyFilesEvenForTheRequestedAccount() async throws {
        let directory = temporaryDirectory()
        let cache = HistoryCache(directory: directory)
        _ = try await seed(cache, key: key())
        try FileManager.default.removeItem(at: directory.appendingPathComponent("active-account"))
        let loaded = try await HistoryCache(directory: directory).load(for: key())
        XCTAssertNil(loaded.cached)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                       ["active-account"])
    }

    func testSwitchRejectsOldSyncFinishingAfterNewSync() async throws {
        let directory = temporaryDirectory()
        let cache = HistoryCache(directory: directory)
        let server = URL(string: "https://history.test")!
        let oldConfig = ConnectionConfig(serverURL: server, bossToken: "synthetic-old")
        let newConfig = ConnectionConfig(serverURL: server, bossToken: "synthetic-new")
        let oldAPI = HistoryTestAPI([HistoryResponse(messages: [historyRow("old")], total: 1)],
                                    config: oldConfig, identity: "boss")
        let newAPI = HistoryTestAPI([HistoryResponse(messages: [historyRow("new")], total: 1)],
                                    config: newConfig, identity: "boss")
        await oldAPI.blockNext()
        let oldSync = HistorySync(api: oldAPI, cache: cache) { _, _ in }
        let newSync = HistorySync(api: newAPI, cache: cache) { _, _ in }
        let oldFetch = Task { await oldSync.synchronize() }
        await oldAPI.waitForRequests(1)
        await newSync.synchronize()
        await oldAPI.release()
        await oldFetch.value
        let saved = try await cache.load(for: HistoryCacheKey(config: newConfig)).cached
        XCTAssertEqual(saved?.1.messages.first?.id, "new")
        await oldSync.stop()
        await newSync.stop()
    }

    func testSaveBeforeActivationIsDroppedAndColdSignOutRemovesMarker() async throws {
        let directory = temporaryDirectory()
        let cache = HistoryCache(directory: directory)
        try await cache.save(HistorySnapshot(), bossID: "boss", key: key(), epoch: 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        _ = try await seed(cache, key: key())
        try await HistoryCache(directory: directory).delete(serverURL: URL(string: "https://history.test")!)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func key(
        server: String = "https://history.test", token: String = "synthetic-first"
    ) -> HistoryCacheKey {
        HistoryCacheKey(config: ConnectionConfig(serverURL: URL(string: server)!, bossToken: token))
    }

    private func seed(_ cache: HistoryCache, key: HistoryCacheKey, row: String = "old") async throws -> Int {
        let epoch = try await cache.load(for: key).epoch
        try await cache.save(HistorySnapshot(messages: [historyRow(row)]), bossID: "boss",
                             key: key, epoch: epoch)
        return epoch
    }
}
