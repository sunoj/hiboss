// Coverage for safe connection restoration on iOS.
// Exports: ConnectionStoreTests.
// Dependencies: XCTest, HibossKit storage contracts, and the HiBoss app target.

import Foundation
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class ConnectionStoreTests: XCTestCase {
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
