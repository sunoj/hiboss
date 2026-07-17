// Persists connection and presentation preferences, with tokens in Keychain.
// Exports: AppSettings, OptionPresentationMode, and TokenStoring.
// Dependencies: Foundation UserDefaults, Combine observation, and Security Keychain.

import Combine
import Foundation
import Security

enum SettingsError: Error, LocalizedError {
    case invalidServerURL
    case missingToken
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter a valid HTTP or HTTPS server URL."
        case .missingToken: "Enter a Boss Token."
        case let .keychain(status): "Keychain operation failed (\(status))."
        }
    }
}

enum OptionPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case island
    case window

    var id: String { rawValue }

    var label: String {
        switch self {
        case .island: "Island"
        case .window: "Window"
        }
    }
}

protocol TokenStoring: Sendable {
    func read() throws -> String?
    func write(_ token: String) throws
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var serverAddress: String
    @Published var bossToken: String
    @Published var presentationMode: OptionPresentationMode {
        didSet { defaults.set(presentationMode.rawValue, forKey: AppConstants.Storage.presentationMode) }
    }
    @Published var showsStatusItem: Bool {
        didSet { defaults.set(showsStatusItem, forKey: AppConstants.Storage.showsStatusItem) }
    }
    @Published var playsSound: Bool {
        didSet { defaults.set(playsSound, forKey: AppConstants.Storage.playsSound) }
    }
    @Published var alertSound: OptionSound {
        didSet { defaults.set(alertSound.rawValue, forKey: AppConstants.Storage.alertSound) }
    }

    private let defaults: UserDefaults
    private let keychain: any TokenStoring

    init(
        defaults: UserDefaults = .standard,
        keychain: any TokenStoring = KeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        serverAddress = defaults.string(forKey: AppConstants.Storage.serverURL) ?? ""
        bossToken = ""
        presentationMode = OptionPresentationMode(
            rawValue: defaults.string(forKey: AppConstants.Storage.presentationMode) ?? ""
        ) ?? .island
        showsStatusItem = defaults.object(forKey: AppConstants.Storage.showsStatusItem) == nil
            ? true
            : defaults.bool(forKey: AppConstants.Storage.showsStatusItem)
        playsSound = defaults.object(forKey: AppConstants.Storage.playsSound) == nil
            ? true
            : defaults.bool(forKey: AppConstants.Storage.playsSound)
        alertSound = OptionSound(
            rawValue: defaults.string(forKey: AppConstants.Storage.alertSound) ?? ""
        ) ?? .fallback
    }

    func loadToken() async {
        let keychain = keychain
        let storedToken = try? await Task.detached(priority: .userInitiated) {
            try keychain.read()
        }.value
        bossToken = storedToken ?? ""
    }

    var isConfigured: Bool {
        switch connectionConfig() {
        case .success: true
        case .failure: false
        }
    }

    func connectionConfig() -> Result<ConnectionConfig, SettingsError> {
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

    func save() -> Result<ConnectionConfig, SettingsError> {
        let result = connectionConfig()
        guard case let .success(config) = result else { return result }
        do {
            try keychain.write(config.bossToken)
            defaults.set(config.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
            return .success(config)
        } catch let error as SettingsError {
            return .failure(error)
        } catch {
            return .failure(.keychain(errSecIO))
        }
    }
}

struct KeychainStore: TokenStoring {
    func read() throws -> String? {
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

    func write(_ token: String) throws {
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
            kSecAttrService as String: AppConstants.Storage.keychainService,
            kSecAttrAccount as String: AppConstants.Storage.keychainAccount,
        ]
    }
}
