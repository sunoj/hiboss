// Covers explicit registration eligibility, credential activation, and retry safety.
// Exports: DeviceRegistrationTests with isolated client inventories.
// Dependencies: XCTest and HibossKit; no live server or Keychain access.

import XCTest
@testable import HibossKit

@MainActor
final class DeviceRegistrationTests: XCTestCase {
    func testMismatchedKindRegistersAndRefreshesWithNewCredentials() async throws {
        let old = try RegistrationAPI(kind: .web)
        let native = try RegistrationAPI(kind: .macos)
        let store = BossClientsStore(api: old)
        await store.load()
        var token = "legacy"
        await store.register(kind: .macos, label: "Office Mac") {
            token = $0
            return native
        }
        XCTAssertEqual(token, "device-token")
        XCTAssertFalse(store.needsRegistration(kind: .macos))
        XCTAssertNil(store.registrationNotice)
        let labels = await old.labels
        XCTAssertEqual(labels, ["macos:Office Mac"])
        let loads = await native.loads
        XCTAssertEqual(loads, 1)
    }

    func testMissingCurrentClientCanRegister() async throws {
        let api = try RegistrationAPI(kind: .ios, current: false)
        let store = BossClientsStore(api: api)
        await store.load()
        XCTAssertTrue(store.needsRegistration(kind: .ios))
        await store.register(kind: .ios, label: "Phone") { _ in api }
        let labels = await api.labels
        XCTAssertEqual(labels, ["ios:Phone"])
    }

    func testNativeClientDoesNotRegister() async throws {
        let api = try RegistrationAPI(kind: .macos)
        let store = BossClientsStore(api: api)
        await store.load()
        await store.register(kind: .macos, label: "Mac") { _ in
            XCTFail("Native credentials must not be replaced")
            return api
        }
        let labels = await api.labels
        XCTAssertTrue(labels.isEmpty)
    }

    func testRegistrationFailureKeepsTokenAndCompatibilityNotice() async throws {
        let api = try RegistrationAPI(kind: .web, fails: true)
        let store = BossClientsStore(api: api)
        await store.load()
        var token = "legacy"
        await store.register(kind: .macos, label: "Mac") { token = $0; return api }
        XCTAssertEqual(token, "legacy")
        XCTAssertEqual(store.registrationNotice, ManualClientLogin.compatibilityNotice)
        XCTAssertTrue(store.needsRegistration(kind: .macos))
        XCTAssertFalse(store.isBusy)
    }

    func testPersistenceFailureRetainsInventoryAndAllowsRetry() async throws {
        let api = try RegistrationAPI(kind: .web)
        let store = BossClientsStore(api: api)
        await store.load()
        await store.register(kind: .macos, label: "Mac") { _ in
            throw SettingsError.keychain(-1)
        }
        XCTAssertEqual(store.clients.first?.kind, .web)
        XCTAssertEqual(store.registrationNotice, ManualClientLogin.compatibilityNotice)
        XCTAssertTrue(store.needsRegistration(kind: .macos))
    }

    func testUnloadedInventoryCannotRegister() async throws {
        let api = try RegistrationAPI(kind: .web)
        let store = BossClientsStore(api: api)
        await store.register(kind: .macos, label: "Mac") { _ in api }
        let labels = await api.labels
        XCTAssertTrue(labels.isEmpty)
    }

    func testRefreshFailureAfterActivationDoesNotRegisterTwice() async throws {
        let old = try RegistrationAPI(kind: .web)
        let native = try RegistrationAPI(kind: .macos)
        await native.failListing()
        let store = BossClientsStore(api: old)
        await store.load()
        var token = "legacy"
        await store.register(kind: .macos, label: "Mac") { token = $0; return native }
        await store.register(kind: .macos, label: "Mac") { _ in
            XCTFail("Refresh failure must not mint another token")
            return native
        }
        XCTAssertEqual(token, "device-token")
        XCTAssertNotNil(store.error)
        XCTAssertNil(store.registrationNotice)
        XCTAssertFalse(store.needsRegistration(kind: .macos))
        let labels = await old.labels
        XCTAssertEqual(labels.count, 1)
    }
}

private actor RegistrationAPI: BossClientsServing {
    let client: BossClient
    let fails: Bool
    var labels: [String] = []
    var loads = 0
    private var listingFails = false

    func failListing() { listingFails = true }

    init(kind: BossClientKind, current: Bool = true, fails: Bool = false) throws {
        self.fails = fails
        let json = """
        {"id":"client","kind":"\(kind.rawValue)","label":"Device","created_at":"2026-09-11",
        "has_push_device":false,"has_signing_key":false,"is_current":\(current)}
        """
        client = try JSONDecoder().decode(BossClient.self, from: Data(json.utf8))
    }

    func verifyConnection() async throws { XCTFail("Use the current connection directly") }
    func listClients() async throws -> [BossClient] {
        loads += 1
        if listingFails { throw HibossAPIError.invalidResponse }
        return [client]
    }
    func createClient(kind: BossClientKind, label: String) async throws -> BossClientGrant {
        labels.append("\(kind.rawValue):\(label)")
        if fails { throw HibossAPIError.invalidResponse }
        return BossClientGrant(client: client, token: "device-token")
    }
    func revokeClient(id: BossClientID) async throws { XCTFail("Shared tokens must stay valid") }
}
