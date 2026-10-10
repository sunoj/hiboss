// Verifies account replacement purges disk history before publishing the new connection.
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
        let saved = try await cache.load(for: key)
        XCTAssertNotNil(saved)
    }

    func testReloadingChangedServerPurgesPreviousCache() async throws {
        let (settings, cache, key, _) = try await fixture()
        settings.serverAddress = "https://replacement.test"
        await settings.loadToken()
        let saved = try await cache.load(for: key)
        XCTAssertNil(saved)
    }

    private enum Replacement { case connect, pair, adopt, activate }
    private static let grant = PairingRedemptionGrant(
        token: "synthetic-new", bossID: "new-boss", signingKeyID: nil
    )

    private func checkReplacement(_ replacement: Replacement) async throws {
        for server in ["https://cached.test", "https://replacement.test"] {
            let (settings, cache, key, root) = try await fixture()
            let previous = try XCTUnwrap(settings.activeClientConfig)
            var retainedAtPublication = false
            let observation = settings.$activeClientConfig.dropFirst().sink { candidate in
                if candidate != previous {
                    retainedAtPublication = FileManager.default.fileExists(atPath: root.path)
                }
            }
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
                _ = try await settings.adopt(Self.grant, server: URL(string: server)!)
            case .activate:
                _ = try await settings.activateDeviceToken("synthetic-new", replacing: previous)
            }
            observation.cancel()
            XCTAssertFalse(retainedAtPublication)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            try await cache.save(HistorySnapshot(), bossID: "old-boss", key: key, epoch: 0)
            let stale = try await cache.load(for: key)
            XCTAssertNil(stale, "An outstanding old-account save must not recreate the cache")
        }
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
        try await cache.save(HistorySnapshot(), bossID: "old-boss", key: key, epoch: 0)
        defaults.set(config.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
        let settings = AppSettings(defaults: defaults, historyCache: cache,
            keychain: ReplacementTokens(), clientsAPI: { _ in ReplacementClientsAPI() },
            redeemer: ReplacementPairingAPI())
        await settings.loadToken()
        return (settings, cache, key, directory.appendingPathComponent(key.server))
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
