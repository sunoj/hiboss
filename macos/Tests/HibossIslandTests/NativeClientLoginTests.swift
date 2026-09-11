// Verifies manual token exchange, fallback notices, and unchanged restoration.
// Exports: NativeClientLoginTests using isolated defaults and in-memory credentials.
// Dependencies: XCTest, HibossKit, and the native connection store.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

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
        XCTAssertEqual(calls, ["verify", "create:macos:Office device"])
        XCTAssertEqual(try store.connectionConfig().get().bossToken, "fresh-token")
        store.bossToken = "unsaved-token"
        XCTAssertEqual(store.activeClientConfig?.bossToken, "fresh-token")
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
        await store.loadToken()
        XCTAssertEqual(store.bossToken, "existing-token")
        XCTAssertEqual(try tokens.read(), "existing-token")
        let calls = await api.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testReconnectOfStoredConnectionDoesNotMintAnotherClient() async throws {
        let (store, tokens, api) = try fixture(stored: "existing-token")
        await store.loadToken()
        _ = try await store.connect().get()
        XCTAssertEqual(try tokens.read(), "existing-token")
        let calls = await api.calls
        XCTAssertEqual(calls, ["verify"])
    }

    func testLegacyRegistrationPersistsActiveTokenDespiteUnsavedEdits() async throws {
        let (store, tokens, api) = try fixture(stored: "existing-token")
        await store.loadToken()
        let current = try XCTUnwrap(store.activeClientConfig)
        store.bossToken = "unsaved-token"
        let inventory = BossClientsStore(api: api)
        await inventory.load()
        await inventory.register(kind: .macos, label: "Office Mac") { token in
            let accepted = try store.activateDeviceToken(token, replacing: current)
            XCTAssertEqual(accepted.serverURL, current.serverURL)
            return api
        }
        XCTAssertEqual(try tokens.read(), "fresh-token")
        XCTAssertEqual(store.activeClientConfig?.bossToken, "fresh-token")
        XCTAssertEqual(store.bossToken, "fresh-token")
        let calls = await api.calls
        XCTAssertEqual(calls, ["create:macos:Office Mac"])
    }

    func testNativeRegistrationDoesNotReplaceStoredToken() async throws {
        let (store, tokens, api) = try fixture(stored: "existing-token")
        await store.loadToken()
        await api.setCurrentKind(.macos)
        let inventory = BossClientsStore(api: api)
        await inventory.load()
        await inventory.register(kind: .macos, label: "Mac") { _ in
            XCTFail("Already native")
            return api
        }
        XCTAssertEqual(try tokens.read(), "existing-token")
        let calls = await api.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testFailedLegacyRegistrationKeepsStoredAndActiveToken() async throws {
        let (store, tokens, api) = try fixture(exchangeFails: true, stored: "existing-token")
        await store.loadToken()
        let current = try XCTUnwrap(store.activeClientConfig)
        let inventory = BossClientsStore(api: api)
        await inventory.load()
        await inventory.register(kind: .macos, label: "Mac") { token in
            _ = try store.activateDeviceToken(token, replacing: current)
            return api
        }
        XCTAssertEqual(try tokens.read(), "existing-token")
        XCTAssertEqual(store.activeClientConfig, current)
        XCTAssertEqual(inventory.registrationNotice, ManualClientLogin.compatibilityNotice)
    }

    func testFailedKeychainWriteKeepsActiveTokenAndShowsCompatibilityNotice() async throws {
        let (store, tokens, api) = try fixture(stored: "existing-token")
        await store.loadToken()
        let current = try XCTUnwrap(store.activeClientConfig)
        tokens.failWrites()
        let inventory = BossClientsStore(api: api)
        await inventory.load()
        await inventory.register(kind: .macos, label: "Mac") { token in
            _ = try store.activateDeviceToken(token, replacing: current)
            return api
        }
        XCTAssertEqual(try tokens.read(), "existing-token")
        XCTAssertEqual(store.activeClientConfig, current)
        XCTAssertEqual(store.bossToken, "existing-token")
        XCTAssertEqual(inventory.registrationNotice, ManualClientLogin.compatibilityNotice)
    }

    func testStaleRegistrationCannotReplaceNewerConnection() async throws {
        let (store, tokens, _) = try fixture(stored: "existing-token")
        await store.loadToken()
        let current = try XCTUnwrap(store.activeClientConfig)
        _ = try store.activateDeviceToken("newer-token", replacing: current)
        XCTAssertThrowsError(try store.activateDeviceToken("stale-token", replacing: current))
        XCTAssertEqual(try tokens.read(), "newer-token")
    }

    private func fixture(
        exchangeFails: Bool = false, verificationFails: Bool = false, stored: String? = nil
    ) throws -> (AppSettings, ClientLoginTokens, ClientLoginAPI) {
        let suite = "NativeClientLoginTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://hiboss.example", forKey: AppConstants.Storage.serverURL)
        let tokens = ClientLoginTokens(token: stored)
        let api = ClientLoginAPI(exchangeFails: exchangeFails, verificationFails: verificationFails)
        let store = AppSettings(defaults: defaults, keychain: tokens, clientsAPI: { config in
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
    private var currentKind: BossClientKind = .web

    func setCurrentKind(_ kind: BossClientKind) { currentKind = kind }

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
        let json = #"{"id":"new-client","kind":"macos","label":"Office device","created_at":"2026-09-11 10:00:00","last_seen_at":null,"revoked_at":null,"has_push_device":false,"has_signing_key":false,"is_current":false}"#
        let client = try JSONDecoder().decode(BossClient.self, from: Data(json.utf8))
        return BossClientGrant(client: client, token: "fresh-token")
    }

    func listClients() async throws -> [BossClient] {
        let json = """
        {"id":"current","kind":"\(currentKind.rawValue)","label":"migrated","created_at":"2026-09-11",
        "has_push_device":false,"has_signing_key":false,"is_current":true}
        """
        return [try JSONDecoder().decode(BossClient.self, from: Data(json.utf8))]
    }
    func revokeClient(id: BossClientID) async throws { XCTFail("Login must not revoke clients") }
}

private final class ClientLoginTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var writesFail = false
    init(token: String?) { self.token = token }
    func read() throws -> String? { lock.withLock { token } }
    func failWrites() { lock.withLock { writesFail = true } }
    func write(_ token: String) throws {
        try lock.withLock {
            if writesFail { throw SettingsError.keychain(-1) }
            self.token = token
        }
    }
}
