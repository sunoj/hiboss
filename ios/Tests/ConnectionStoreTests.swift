// Coverage for safe connection restoration on iOS.
// Exports: ConnectionStoreTests.
// Dependencies: XCTest, HibossKit storage contracts, and the HiBoss app target.

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
