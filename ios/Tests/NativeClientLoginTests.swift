// Verifies manual token exchange, fallback notices, and unchanged restoration.
// Exports: NativeClientLoginTests using isolated defaults and in-memory credentials.
// Dependencies: XCTest, HibossKit, and the native connection store.

import Combine
import Foundation
@testable import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class NativeClientLoginTests: XCTestCase {
    func testExchangeReplacesPastedTokenAndUsesEditableDeviceLabel() async throws {
        let (store, tokens, api) = try fixture()
        store.deviceLabel = "Office device"
        _ = try await store.connect().get()
        XCTAssertEqual(try tokens.read(), "fresh-token")
        XCTAssertEqual(store.bossToken, "fresh-token")
        XCTAssertNil(store.clientExchangeNotice)
        let calls = await api.calls
        XCTAssertEqual(calls, ["verify", "create:ios:Office device"])
        XCTAssertEqual(store.config?.bossToken, "fresh-token")
    }

    func testExchangeFailureKeepsPastedTokenAndSurfacesNotice() async throws {
        let (store, tokens, api) = try fixture(exchangeFails: true)
        _ = try await store.connect().get()
        XCTAssertEqual(try tokens.read(), "pasted-token")
        XCTAssertEqual(store.bossToken, "pasted-token")
        XCTAssertFalse(try XCTUnwrap(store.clientExchangeNotice).isEmpty)
        let calls = await api.calls
        XCTAssertEqual(calls.count, 2)
    }

    func testRejectedPastedTokenIsNeverExchangedOrPersisted() async throws {
        let (store, tokens, api) = try fixture(verificationFails: true)
        guard case .failure = await store.connect() else { return XCTFail("Expected rejected token") }
        XCTAssertNil(try tokens.read())
        XCTAssertNil(store.clientExchangeNotice)
        let calls = await api.calls
        XCTAssertEqual(calls, ["verify"])
    }

    func testRestoreRetainsStoredTokenWithoutExchange() async throws {
        let (store, tokens, api) = try fixture(stored: "existing-token")
        await store.restore()
        XCTAssertEqual(store.bossToken, "existing-token")
        XCTAssertEqual(try tokens.read(), "existing-token")
        let calls = await api.calls
        XCTAssertTrue(calls.isEmpty)
    }


    private func fixture(
        exchangeFails: Bool = false, verificationFails: Bool = false, stored: String? = nil
    ) throws -> (ConnectionStore, ClientLoginTokens, ClientLoginAPI) {
        let suite = "NativeClientLoginTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://hiboss.example", forKey: AppConstants.Storage.serverURL)
        let tokens = ClientLoginTokens(token: stored)
        let api = ClientLoginAPI(exchangeFails: exchangeFails, verificationFails: verificationFails)
        let store = ConnectionStore(defaults: defaults, keychain: tokens, signerStore: ClientLoginSignerStore(), clientsAPI: { config in
            XCTAssertEqual(config.bossToken, stored ?? "pasted-token")
            return api
        })
        store.bossToken = "pasted-token"
        return (store, tokens, api)
    }
}

private actor ClientLoginAPI: BossClientsServing {
    let exchangeFails: Bool
    let verificationFails: Bool
    var calls: [String] = []

    init(exchangeFails: Bool, verificationFails: Bool) {
        self.exchangeFails = exchangeFails
        self.verificationFails = verificationFails
    }

    func verifyConnection() async throws {
        calls.append("verify")
        if verificationFails { throw HibossAPIError.requestFailed(status: 401, message: "") }
    }

    func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        calls.append("create:\(kind.rawValue):\(label)")
        if exchangeFails { throw HibossAPIError.requestFailed(status: 404, message: "") }
        let json = #"{"id":"new-client","kind":"ios","label":"Office device","created_at":"2026-09-11 10:00:00","last_seen_at":null,"revoked_at":null,"has_push_device":false,"has_signing_key":false,"is_current":false}"#
        let client = try JSONDecoder().decode(BossClient.self, from: Data(json.utf8))
        return BossClientGrant(client: client, token: "fresh-token")
    }

    func listClients() async throws -> [BossClient] { [] }
    func revokeClient(id: BossClientID) async throws { XCTFail("Login must not revoke clients") }
}

private final class ClientLoginTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    init(token: String?) { self.token = token }
    func read() throws -> String? { lock.withLock { token } }
    func write(_ token: String) throws { lock.withLock { self.token = token } }
}

private struct ClientLoginSignerStore: MessageSignerStoring {
    func read() throws -> SecureEnclaveMessageSigner? { nil }
    func write(_ signer: SecureEnclaveMessageSigner) throws {}
    func delete() throws {}
}

// Account changes purge disk history before publishing the replacement connection.
@MainActor
final class AccountHistoryReplacementTests: XCTestCase {
    func testDirectConnectPurgesPreviousAccountOnSameAndDifferentServers() async throws {
        try await checkReplacement(.connect)
    }

    func testPairingPurgesPreviousAccountOnSameAndDifferentServers() async throws {
        try await checkReplacement(.pair)
    }

    func testDeviceTokenActivationPurgesPreviousCredentialCache() async throws {
        try await checkReplacement(.activate)
    }

    func testReconnectRetainsUnchangedCredentialCache() async throws {
        let (connection, cache, key, _) = try await fixture()
        _ = try await connection.connect().get()
        let saved = try await cache.load(for: key)
        XCTAssertNotNil(saved)
    }

    func testRestoringChangedServerPurgesPreviousCache() async throws {
        let (connection, cache, key, _) = try await fixture()
        connection.serverAddress = "https://replacement.test"
        await connection.restore()
        let saved = try await cache.load(for: key)
        XCTAssertNil(saved)
    }

    func testInvalidRestorationPurgesPreviousCache() async throws {
        let (connection, cache, key, _) = try await fixture()
        connection.serverAddress = ""
        await connection.restore()
        let saved = try await cache.load(for: key)
        XCTAssertNil(saved)
        XCTAssertNil(connection.config)
    }

    private enum Replacement { case connect, pair, activate }

    private func checkReplacement(_ replacement: Replacement) async throws {
        for server in ["https://cached.test", "https://replacement.test"] {
            let (connection, cache, key, root) = try await fixture()
            let previous = try XCTUnwrap(connection.config)
            var retainedAtPublication = false
            let observation = connection.$config.dropFirst().sink { candidate in
                if candidate != previous {
                    retainedAtPublication = FileManager.default.fileExists(atPath: root.path)
                }
            }
            switch replacement {
            case .connect:
                connection.serverAddress = server
                connection.bossToken = "synthetic-new"
                _ = try await connection.connect().get()
            case .pair:
                let payload = try PairingPayload.make(server: server,
                    code: "hb_pair_" + String(repeating: "d", count: 64)).get()
                _ = try await connection.pair(payload: payload, deviceLabel: "Test device").get()
            case .activate:
                _ = try await connection.activateDeviceToken("synthetic-new", replacing: previous)
            }
            observation.cancel()
            XCTAssertFalse(retainedAtPublication)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            try await cache.save(HistorySnapshot(), bossID: "old-boss", key: key, epoch: 0)
            let stale = try await cache.load(for: key)
            XCTAssertNil(stale, "An outstanding old-account save must not recreate the cache")
        }
    }

    private func fixture() async throws -> (ConnectionStore, HistoryCache, HistoryCacheKey, URL) {
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
        let connection = ConnectionStore(defaults: defaults, historyCache: cache,
            keychain: ReplacementTokens(), sharedDefaults: nil, signerStore: ReplacementSignerStore(),
            pairingRedeemer: ReplacementPairingAPI(), clientsAPI: { _ in ReplacementClientsAPI() })
        await connection.restore()
        return (connection, cache, key, directory.appendingPathComponent(key.server))
    }
}

private final class ReplacementTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token = "synthetic-old"
    func read() throws -> String? { lock.withLock { token } }
    func write(_ token: String) throws { lock.withLock { self.token = token } }
}

private struct ReplacementSignerStore: MessageSignerStoring {
    func read() throws -> SecureEnclaveMessageSigner? { nil }
    func write(_ signer: SecureEnclaveMessageSigner) throws {}
    func delete() throws {}
}

private struct ReplacementClientsAPI: BossClientsServing {
    func verifyConnection() async throws {}
    func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        throw HibossAPIError.requestFailed(status: 404, message: "")
    }
    func listClients() async throws -> [BossClient] { [] }
    func revokeClient(id: BossClientID) async throws { XCTFail("Unexpected revocation") }
}

private struct ReplacementPairingAPI: ConnectionPairingRedeeming {
    func redeem(payload: PairingPayload, deviceLabel: String) async throws -> PairingRedemption {
        PairingRedemption(token: "synthetic-new", signer: SecureEnclaveMessageSigner(
            keyRepresentation: Data(), keyID: "synthetic-key", bossID: "new-boss", clientKind: .ios
        ))
    }
}
