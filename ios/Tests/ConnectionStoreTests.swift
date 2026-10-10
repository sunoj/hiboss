// Coverage for safe connection restoration on iOS.
// Exports: ConnectionStoreTests.
// Dependencies: XCTest, HibossKit storage contracts, and the HiBoss app target.

import Combine
import Foundation
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class ConnectionStoreTests: XCTestCase {
    func testLaunchMigratesTokenPublishesURLAndSignOutClearsSharedURL() async throws {
        let suiteName = "ConnectionMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName + ".shared"))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            sharedDefaults.removePersistentDomain(forName: suiteName + ".shared")
        }
        defaults.set("https://example.com", forKey: AppConstants.Storage.serverURL)
        let old = MigrationTokenStore("fixture")
        let shared = MigrationTokenStore(nil)
        let signer = CountingSignerStore()
        let store = ConnectionStore(defaults: defaults, keychain: shared, legacyKeychain: old,
            sharedDefaults: sharedDefaults, signerStore: signer)
        await store.restore()
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(shared.value, "fixture")
        XCTAssertNil(old.value)
        XCTAssertEqual(signer.deletes, 0)
        XCTAssertEqual(sharedDefaults.string(forKey: AppConstants.Storage.serverURL), "https://example.com")
        store.signOut()
        XCTAssertNil(sharedDefaults.string(forKey: AppConstants.Storage.serverURL))
    }

    func testFailedLaunchMigrationKeepsPrivateTokenAndRetriesNextLaunch() async throws {
        let suiteName = "ConnectionMigrationRetry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://example.com", forKey: AppConstants.Storage.serverURL)
        let old = MigrationTokenStore("fixture")
        let shared = MigrationTokenStore(nil)
        shared.failWrite = true
        let store = ConnectionStore(defaults: defaults, keychain: shared, legacyKeychain: old,
            sharedDefaults: nil, signerStore: StubSignerStore())
        await store.restore()
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(old.value, "fixture")
        XCTAssertNil(shared.value)
        shared.failWrite = false
        await store.restore()
        XCTAssertEqual(shared.value, "fixture")
        XCTAssertNil(old.value)
    }

    func testSignOutDeletesLegacyTokenAfterFailedMigration() async throws {
        let suiteName = "ConnectionSignOut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://example.com", forKey: AppConstants.Storage.serverURL)
        let old = MigrationTokenStore("fixture")
        let shared = MigrationTokenStore(nil)
        shared.failWrite = true
        let store = ConnectionStore(defaults: defaults, keychain: shared, legacyKeychain: old,
            sharedDefaults: nil, signerStore: StubSignerStore())
        await store.restore()
        XCTAssertTrue(store.isConfigured)
        XCTAssertEqual(old.deletes, 0)
        store.signOut()
        XCTAssertNil(old.value)
        XCTAssertEqual(old.deletes, 1)
        XCTAssertFalse(store.isConfigured)
        shared.failWrite = false
        await store.restore()
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(shared.value)
    }

    func testRestoreDoesNotExposeOrphanTokenWithoutServerURL() async throws {
        let suiteName = "ConnectionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ConnectionStore(
            defaults: defaults,
            keychain: StubTokenStore(token: "orphan-token"),
            signerStore: StubSignerStore()
        )

        await store.restore()

        XCTAssertEqual(store.serverAddress, "")
        XCTAssertEqual(store.bossToken, "")
        XCTAssertFalse(store.isConfigured)
    }
}

private struct StubTokenStore: TokenStoring {
    let token: String?

    func read() throws -> String? { token }
    func write(_ token: String) throws {}
}

private struct StubSignerStore: MessageSignerStoring {
    func read() throws -> SecureEnclaveMessageSigner? { nil }
    func write(_ signer: SecureEnclaveMessageSigner) throws {}
    func delete() throws {}
}

private final class CountingSignerStore: MessageSignerStoring, @unchecked Sendable {
    var deletes = 0
    func read() throws -> SecureEnclaveMessageSigner? { nil }
    func write(_ signer: SecureEnclaveMessageSigner) throws {}
    func delete() throws { deletes += 1 }
}

@MainActor
final class HistoryCacheIntegrationTests: XCTestCase {
    func testInboxDoesNotPublishIdenticalDeltaOrEmptyDelta() async {
        let api = CachedInboxAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: api)
        await store.historyTask?.value
        var publications = 0
        let observation = store.$history.dropFirst().sink { _ in publications += 1 }
        store.requestHistorySync()
        await store.historyTask?.value
        store.requestHistorySync()
        await store.historyTask?.value
        XCTAssertEqual(store.history.map(\.id), ["cached"])
        XCTAssertEqual(publications, 0)
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, "2026-10-10 10:20:30", "2026-10-10 10:20:30"])
        observation.cancel()
        store.stop()
    }

    func testSignOutDeletesPersistedHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "HistorySignOut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let config = ConnectionConfig(serverURL: URL(string: "https://cached.test")!, bossToken: "synthetic")
        let cache = HistoryCache(directory: directory)
        let sync = HistorySync(api: CachedInboxAPI(config: config), cache: cache) { _, _ in }
        await sync.synchronize()
        await sync.stop()
        let roots = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        let root = try XCTUnwrap(roots.first { $0.lastPathComponent != "active-account" })
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty)
        for file in files {
            // Simulator files do not expose the device Data Protection attribute.
            #if !targetEnvironment(simulator)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual(attributes[.protectionKey] as? String,
                           FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            #endif
            let values = try file.resourceValues(forKeys: [.isExcludedFromBackupKey])
            XCTAssertTrue(values.isExcludedFromBackup == true)
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains(config.bossToken))
        }
        defaults.set(config.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
        let connection = ConnectionStore(defaults: defaults, historyCache: cache,
            keychain: HistoryTokenFixture(), sharedDefaults: nil)
        await connection.restore()
        connection.signOut()
        await connection.historyCacheDeletion?.value
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        XCTAssertFalse(connection.isConfigured)
    }
}

private actor CachedInboxAPI: BossServing {
    let config: ConnectionConfig?
    var cursors: [String?] = []
    init(config: ConnectionConfig? = nil) { self.config = config }
    nonisolated var historyCacheKey: HistoryCacheKey? { config.map { HistoryCacheKey(config: $0) } }
    func fetchHistoryBossID() async throws -> String? { "boss" }
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        cursors.append(updatedAfter)
        let row = HistoryMessage(id: "cached", body: "Cached", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "2026-10-01T00:00:00Z")
        return HistoryResponse(messages: cursors.count == 3 ? [] : [row], total: 1,
                               cursor: "2026-10-10 10:20:30")
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}

private struct HistoryTokenFixture: TokenStoring {
    func read() throws -> String? { "synthetic" }
    func write(_ token: String) throws {}
}
