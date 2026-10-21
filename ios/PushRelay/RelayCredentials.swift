// This install's push-relay credentials, kept in the keychain group shared with the NSE.
// Exports: RelayCredentials, RelayCredentialStoring and KeychainRelayCredentialStore.
// Dependencies: Foundation and the Security keychain APIs.

import Foundation
import Security

/// `handle` and `deviceSecret` are minted by the relay; `pushKey` is base64url AES-256 key
/// material generated on this device. None of them is ever logged.
struct RelayCredentials: Codable, Equatable, Sendable {
    let handle: String
    let deviceSecret: String
    let pushKey: String
    var apnsToken: String
    var environment: String

    /// The server's device id for a relay registration.
    var serverDeviceID: String { "relay:\(handle)" }
}

protocol RelayCredentialStoring: Sendable {
    func read() throws -> RelayCredentials?
    func write(_ credentials: RelayCredentials) throws
    func delete() throws
}

enum RelayCredentialError: Error {
    case keychain(OSStatus)
}

/// One generic-password item, readable after first unlock so the NSE can decrypt while locked.
struct KeychainRelayCredentialStore: RelayCredentialStoring {
    static let service = "ai.hiboss.app"
    static let account = "push-relay"

    let accessGroup: String?

    init(accessGroup: String? = KeychainRelayCredentialStore.sharedAccessGroup) {
        self.accessGroup = accessGroup
    }

    /// The expanded shared group from Info.plist; nil when the build left it unexpanded.
    static var sharedAccessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainAccessGroup") as? String,
              !group.isEmpty, !group.contains("$(") else { return nil }
        return group
    }

    func read() throws -> RelayCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw RelayCredentialError.keychain(status)
        }
        return try JSONDecoder().decode(RelayCredentials.self, from: data)
    }

    /// Replaces the item so its accessibility class is always the one set here.
    func write(_ credentials: RelayCredentials) throws {
        try delete()
        var item = baseQuery
        item[kSecValueData as String] = try JSONEncoder().encode(credentials)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw RelayCredentialError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RelayCredentialError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
