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
    func testAuthorizationRejectionLeavesTheConnectedShellAndKeepsStoredCredentials() async throws {
        let suite = "ConnectionRejection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let sharedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite + ".shared"))
        defer {
            defaults.removePersistentDomain(forName: suite)
            sharedDefaults.removePersistentDomain(forName: suite + ".shared")
            AccountAuthorization.shared.connect(nil)
        }
        defaults.set("https://example.com", forKey: AppConstants.Storage.serverURL)
        let tokens = MigrationTokenStore("fixture")
        let store = ConnectionStore(defaults: defaults, keychain: tokens, sharedDefaults: sharedDefaults,
                                    signerStore: StubSignerStore())
        await store.restore()
        XCTAssertTrue(store.isConfigured)
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        XCTAssertFalse(store.isConfigured, "A rejected shell must offer sign-in instead of an unusable reconnect")
        XCTAssertNil(store.makeAPI())
        XCTAssertTrue(AccountAuthorization.shared.hasRejectedAccount)
        XCTAssertNil(sharedDefaults.string(forKey: AppConstants.Storage.serverURL))
        XCTAssertEqual(tokens.value, "fixture", "Account invalidation must not delete Keychain credentials")
        XCTAssertEqual(tokens.deletes, 0)
    }

    func testAuthorizationRejectionDeletesTheRelayRegistrationAndErasesIt() async throws {
        let suite = "ConnectionRelayRejection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            AccountAuthorization.shared.connect(nil)
        }
        defaults.set("https://example.com", forKey: AppConstants.Storage.serverURL)
        PushRelayStub.reset()
        let credentials = MemoryRelayCredentialStore()
        try credentials.write(RelayCredentials(handle: "h", deviceSecret: "secret-1", pushKey: "k",
                                               apnsToken: "ab", environment: "sandbox"))
        let relay = PushRelayRegistrar(
            client: PushRelayClient(baseURL: try XCTUnwrap(URL(string: "https://relay.example")),
                                    session: PushRelayStub.session()),
            store: credentials)
        var unregistered: Task<Void, Never>?
        let store = ConnectionStore(defaults: defaults, keychain: MigrationTokenStore("fixture"),
                                    sharedDefaults: nil, signerStore: StubSignerStore(),
                                    onSignOut: { api in unregistered = Task { await relay.unregister(api: api) } })
        await store.restore()
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        AccountAuthorization.shared.reject(HibossAPIError.requestFailed(status: 401, message: ""))
        await unregistered?.value
        XCTAssertEqual(PushRelayStub.routes, ["DELETE relay.example/v1/registrations/self"])
        XCTAssertEqual(PushRelayStub.requests.first?.authorization, "Bearer secret-1")
        XCTAssertNil(try credentials.read())
        XCTAssertFalse(store.isConfigured)
    }

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
final class HistorySyncIntegrationTests: XCTestCase {
    func testInboxDoesNotPublishIdenticalDeltaOrEmptyDelta() async {
        let api = IncrementalInboxAPI()
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

    func testAPIReplacementDropsHistoryAndIgnoresLateOldSync() async {
        let old = ReplacementInboxAPI(id: "old")
        let current = ReplacementInboxAPI(id: "new")
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: old)
        await store.historyTask?.value
        XCTAssertEqual(store.history.map(\.id), ["old"])
        let started = expectation(description: "old history request started")
        await old.holdNextRequest(started)
        store.requestHistorySync()
        let lateFetch = store.historyTask
        await fulfillment(of: [started], timeout: 2)
        store.start(api: current)
        XCTAssertTrue(store.history.isEmpty)
        await store.historyTask?.value
        XCTAssertEqual(store.history.map(\.id), ["new"])
        await old.release()
        await lateFetch?.value
        XCTAssertEqual(store.history.map(\.id), ["new"])
        let cursors = await current.cursors
        XCTAssertEqual(cursors, [nil])
        store.stop()
    }

    func testPullToRefreshFetchesFullHistory() async {
        let api = IncrementalInboxAPI()
        let store = InboxStore(decisionAlertsEnabled: false)
        store.start(api: api)
        await store.historyTask?.value
        await store.refresh()
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, nil])
        store.stop()
    }
}

private actor IncrementalInboxAPI: BossServing {
    var cursors: [String?] = []
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


// Holds a response after request admission, even when its caller is canceled.
private actor ReplacementInboxAPI: BossServing {
    let id: MessageID
    var cursors: [String?] = []
    private var started: XCTestExpectation?
    private var response: CheckedContinuation<Void, Never>?

    init(id: MessageID) { self.id = id }
    func holdNextRequest(_ started: XCTestExpectation) { self.started = started }
    func release() {
        response?.resume()
        response = nil
    }
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        cursors.append(updatedAfter)
        let held = started != nil
        if let started {
            self.started = nil
            await withCheckedContinuation {
                response = $0
                started.fulfill()
            }
        }
        let rowID = held ? MessageID(rawValue: id.rawValue + "-late") : id
        let row = HistoryMessage(id: rowID, body: "Fixture", direction: "agent_to_boss",
            status: "delivered", priority: "normal", createdAt: "2026-10-01T00:00:00Z")
        return HistoryResponse(messages: [row], total: 1, cursor: id.rawValue)
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
