// Persists connection and presentation preferences, with tokens in Keychain.
// Exports: AppSettings and OptionPresentationMode.
// Dependencies: HibossKit keychain/config, Foundation UserDefaults, and Combine.

import Combine
import Foundation
import HibossKit
import Security

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
        makeConnectionConfig(serverAddress: serverAddress, bossToken: bossToken)
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
