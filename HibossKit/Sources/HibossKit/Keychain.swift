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
        case .invalidServerURL: kitL("Enter a valid HTTP or HTTPS server URL.")
        case .missingToken: kitL("Enter a Boss Token.")
        case let .keychain(status): kitL("Keychain operation failed (\(status)).")
        }
    }
}

public protocol TokenStoring: Sendable {
    func read() throws -> String?
    func write(_ token: String) throws
}

public protocol TokenRemoving: TokenStoring {
    func delete() throws
}

public struct KeychainStore: TokenRemoving {
    private let service: String
    private let account: String
    private let accessGroup: String?
    private let operations: any KeychainOperating

    public init(
        service: String = AppConstants.Storage.keychainService,
        account: String = AppConstants.Storage.keychainAccount,
        accessGroup: String? = nil
    ) {
        self.init(service: service, account: account, accessGroup: accessGroup,
            operations: SecurityKeychain())
    }

    init(service: String, account: String, accessGroup: String?, operations: any KeychainOperating) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
        self.operations = operations
    }

    public func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, item) = operations.read(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SettingsError.keychain(status) }
        guard let data = item else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ token: String) throws {
        let data = Data(token.utf8)
        let updated = operations.update(baseQuery, data: data)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw SettingsError.keychain(updated) }
        var item = baseQuery
        item[kSecValueData as String] = data
        let status = operations.add(item)
        guard status == errSecSuccess else { throw SettingsError.keychain(status) }
    }

    public func delete() throws {
        let status = operations.delete(baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SettingsError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

/// Validates a server address + token pair into a `ConnectionConfig`.
public func makeConnectionConfig(
    serverAddress: String,
    bossToken: String
) -> Result<ConnectionConfig, SettingsError> {
    let trimmed = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let token = bossToken.trimmingCharacters(in: .whitespacesAndNewlines)
    // Accept a bare host ("hiboss.you.workers.dev") by defaulting to https.
    let address = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let url = URL(string: address),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          url.host != nil else {
        return .failure(.invalidServerURL)
    }
    guard !token.isEmpty else { return .failure(.missingToken) }
    return .success(ConnectionConfig(serverURL: url, bossToken: token))
}
