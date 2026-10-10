// Verifies account replacement clears old disk history when the new history sync starts.
// Covers manual connection, pairing, phone sign-in adoption, and device-token activation.
// Depends on isolated defaults, in-memory tokens, and the real HistoryCache actor.

import Combine
import Foundation
import XCTest
@testable import HibossKit
@testable import HibossIsland

@MainActor
final class AccountHistoryReplacementTests: XCTestCase {
    func testDirectConnectPurgesPreviousAccountOnSameAndDifferentServers() async throws {
        try await checkReplacement(.connect)
    }

    func testPairingPurgesPreviousAccountOnSameAndDifferentServers() async throws {
        try await checkReplacement(.pair)
    }

    func testPhoneSigninAdoptionPurgesPreviousAccountOnSameAndDifferentServers() async throws {
        try await checkReplacement(.adopt)
    }

    func testDeviceTokenActivationPurgesPreviousCredentialCache() async throws {
        try await checkReplacement(.activate)
    }

    func testReconnectRetainsUnchangedCredentialCache() async throws {
        let (settings, cache, key, _) = try await fixture()
        _ = try await settings.connect().get()
        let saved = try await cache.load(for: key).cached
        XCTAssertNotNil(saved)
    }

    func testReloadingChangedServerPurgesPreviousCache() async throws {
        let (settings, cache, key, _) = try await fixture()
        settings.serverAddress = "https://replacement.test"
        await settings.loadToken()
        try await synchronize(try settings.connectionConfig().get(), cache: cache)
        let saved = try await cache.load(for: key).cached
        XCTAssertNil(saved)
    }

    func testMenuReconnectAfterTokenEditClearsOldCacheWithoutAcceptingSettings() async throws {
        let (settings, cache, _, oldLookup) = try await fixture()
        let accepted = settings.activeClientConfig
        settings.bossToken = "synthetic-new"
        // The menu Reconnect action reads the editable config without calling connect().
        try await synchronize(try settings.connectionConfig().get(), cache: cache)
        XCTAssertEqual(settings.activeClientConfig, accepted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLookup.path))
    }

    private enum Replacement { case connect, pair, adopt, activate }
    private static let grant = PairingRedemptionGrant(
        token: "synthetic-new", bossID: "new-boss", signingKeyID: nil
    )

    private func checkReplacement(_ replacement: Replacement) async throws {
        for server in ["https://cached.test", "https://replacement.test"] {
            let (settings, cache, key, root) = try await fixture()
            let previous = try XCTUnwrap(settings.activeClientConfig)
            switch replacement {
            case .connect:
                settings.serverAddress = server
                settings.bossToken = "synthetic-new"
                _ = try await settings.connect().get()
            case .pair:
                let payload = try PairingPayload.make(server: server,
                    code: "hb_pair_" + String(repeating: "d", count: 64)).get()
                _ = try await settings.pair(with: payload).get()
            case .adopt:
                _ = try settings.adopt(Self.grant, server: URL(string: server)!)
            case .activate:
                _ = try settings.activateDeviceToken("synthetic-new", replacing: previous)
            }
            try await synchronize(try settings.connectionConfig().get(), cache: cache)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            try await cache.save(HistorySnapshot(), bossID: "old-boss", key: key, epoch: 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path),
                           "An outstanding old-account save must not recreate the cache")
        }
    }

    private func synchronize(_ config: ConnectionConfig, cache: HistoryCache) async throws {
        let sync = HistorySync(api: ReplacementHistoryAPI(config: config), cache: cache) { _, error in
            XCTAssertNil(error)
        }
        await sync.synchronize()
        await sync.stop()
        let current = try await cache.load(for: HistoryCacheKey(config: config)).cached
        XCTAssertEqual(current?.0, "new-boss")
    }

    private func fixture() async throws -> (AppSettings, HistoryCache, HistoryCacheKey, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "AccountHistoryReplacement.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let config = ConnectionConfig(
            serverURL: URL(string: "https://cached.test")!, bossToken: "synthetic-old"
        )
        let key = HistoryCacheKey(config: config)
        let cache = HistoryCache(directory: directory)
        _ = try await cache.load(for: key)
        try await cache.save(HistorySnapshot(), bossID: "old-boss", key: key, epoch: 0)
        defaults.set(config.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
        let settings = AppSettings(defaults: defaults, historyCache: cache,
            keychain: ReplacementTokens(), clientsAPI: { _ in ReplacementClientsAPI() },
            redeemer: ReplacementPairingAPI())
        await settings.loadToken()
        let lookup = directory.appendingPathComponent(key.server)
            .appendingPathComponent("lookup-" + key.credential)
        return (settings, cache, key, lookup)
    }
}

private final class ReplacementTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token = "synthetic-old"
    func read() throws -> String? { lock.withLock { token } }
    func write(_ token: String) throws { lock.withLock { self.token = token } }
}

private struct ReplacementClientsAPI: BossClientsServing {
    func verifyConnection() async throws {}
    func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        throw HibossAPIError.requestFailed(status: 404, message: "")
    }
    func listClients() async throws -> [BossClient] { [] }
    func revokeClient(id: BossClientID) async throws { XCTFail("Unexpected revocation") }
}

private struct ReplacementPairingAPI: PairingRedeeming {
    func redeem(payload: PairingPayload, deviceLabel: String,
                signing: PairingSigningRegistration?) async throws -> PairingRedemptionGrant {
        PairingRedemptionGrant(token: "synthetic-new", bossID: "new-boss", signingKeyID: nil)
    }
}

private struct ReplacementHistoryAPI: BossServing {
    let config: ConnectionConfig
    var historyCacheKey: HistoryCacheKey? { HistoryCacheKey(config: config) }
    func fetchHistoryBossID() async throws -> String? { "new-boss" }
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        HistoryResponse(messages: [], total: 0, cursor: "2026-10-10 10:20:30")
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
