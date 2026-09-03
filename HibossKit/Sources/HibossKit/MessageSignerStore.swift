// Persists a Secure Enclave key reference and its server-bound identity in Keychain.
// Exports a storage protocol and KeychainMessageSignerStore implementation.
// Depends on Foundation Codable, Security, and SecureEnclaveMessageSigner.

import Foundation
import Security

public enum MessageSignerStoreError: Error, Sendable {
    case keychain(OSStatus)
    case invalidData
}

public protocol MessageSignerStoring: Sendable {
    func read() throws -> SecureEnclaveMessageSigner?
    func write(_ signer: SecureEnclaveMessageSigner) throws
    func delete() throws
}

public struct KeychainMessageSignerStore: MessageSignerStoring {
    private let service: String
    private let account: String

    public init(
        service: String = AppConstants.Storage.keychainService,
        account: String = AppConstants.Storage.signingKeychainAccount
    ) {
        self.service = service
        self.account = account
    }

    public func read() throws -> SecureEnclaveMessageSigner? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw MessageSignerStoreError.keychain(status) }
        guard let data = item as? Data,
              let signer = try? JSONDecoder().decode(SecureEnclaveMessageSigner.self, from: data)
        else {
            throw MessageSignerStoreError.invalidData
        }
        return signer
    }

    public func write(_ signer: SecureEnclaveMessageSigner) throws {
        let data = try JSONEncoder().encode(signer)
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw MessageSignerStoreError.keychain(status) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MessageSignerStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
