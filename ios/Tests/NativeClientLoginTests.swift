// Verifies manual token exchange, fallback notices, and unchanged restoration.
// Exports: NativeClientLoginTests using isolated defaults and in-memory credentials.
// Dependencies: XCTest, HibossKit, and the native connection store.

import Foundation
import HibossKit
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
