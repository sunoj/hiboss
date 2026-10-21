// The relay credentials item round-trips in the shared keychain group, readable after first unlock
// on this device only; an older item is migrated on read.
// Exports: RelayCredentialKeychainTests.
// Dependencies: XCTest, Security, KeychainRelayCredentialStore.

import Security
import XCTest
@testable import HiBoss

final class RelayCredentialKeychainTests: XCTestCase {
    private let store = KeychainRelayCredentialStore()

    override func tearDown() { try? store.delete() }

    func testRoundTripUsesAfterFirstUnlockThisDeviceOnlyInTheSharedGroup() throws {
        XCTAssertNotNil(KeychainRelayCredentialStore.sharedAccessGroup, "the NSE reads the same group")
        let credentials = RelayCredentials(handle: "h", deviceSecret: "s", pushKey: "k",
                                           apnsToken: "ab", environment: "sandbox")
        try store.write(credentials)
        try store.write(credentials)
        XCTAssertEqual(try store.read(), credentials)

        XCTAssertEqual(try accessibility(), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)

        try store.delete()
        XCTAssertNil(try store.read())
    }

    func testReadMigratesAnOlderItemToThisDeviceOnly() throws {
        let credentials = RelayCredentials(handle: "h", deviceSecret: "s", pushKey: "k",
                                           apnsToken: "ab", environment: "sandbox")
        var item = query
        item[kSecValueData as String] = try JSONEncoder().encode(credentials)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        XCTAssertEqual(SecItemAdd(item as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(try accessibility(), kSecAttrAccessibleAfterFirstUnlock as String)

        XCTAssertEqual(try store.read(), credentials)
        XCTAssertEqual(try accessibility(), kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        XCTAssertEqual(try store.read(), credentials)
    }

    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainRelayCredentialStore.service,
            kSecAttrAccount as String: KeychainRelayCredentialStore.account,
        ]
        query[kSecAttrAccessGroup as String] = KeychainRelayCredentialStore.sharedAccessGroup
        return query
    }

    private func accessibility() throws -> String? {
        var query = query
        query[kSecReturnAttributes as String] = true
        var item: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
        return try XCTUnwrap(item as? [String: Any])[kSecAttrAccessible as String] as? String
    }
}
