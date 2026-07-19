// Keychain-backed token storage and connection validation shared by the clients.
// Exports: TokenStoring, KeychainStore, and SettingsError.
// Dependencies: Foundation and the Security Keychain APIs.

import Foundation
import Security

public enum SettingsError: Error, LocalizedError {
    case invalidServerURL
    case missingToken
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter a valid HTTP or HTTPS server URL."
        case .missingToken: "Enter a Boss Token."
        case let .keychain(status): "Keychain operation failed (\(status))."
        }
    }
}

public protocol TokenStoring: Sendable {
    func read() throws -> String?
    func write(_ token: String) throws
}

public struct KeychainStore: TokenStoring {
    private let service: String
    private let account: String

    public init(
        service: String = AppConstants.Storage.keychainService,
        account: String = AppConstants.Storage.keychainAccount
    ) {
        self.service = service
        self.account = account
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SettingsError.keychain(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String) throws {
        let data = Data(token.utf8)
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw SettingsError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Validates a server address + token pair into a `ConnectionConfig`.
public func makeConnectionConfig(
    serverAddress: String,
    bossToken: String
) -> Result<ConnectionConfig, SettingsError> {
    let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let token = bossToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: address),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host != nil else {
        return .failure(.invalidServerURL)
    }
    guard !token.isEmpty else { return .failure(.missingToken) }
    return .success(ConnectionConfig(serverURL: url, bossToken: token))
}
