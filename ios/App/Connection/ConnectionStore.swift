// Holds the boss connection: server URL in defaults, token in the Keychain.
// Exports: ConnectionStore observable used to gate onboarding and build the API.
// Dependencies: HibossKit (KeychainStore, makeConnectionConfig, HibossAPI).

import Combine
import Foundation
import HibossKit

@MainActor
final class ConnectionStore: ObservableObject {
    @Published var serverAddress: String
    @Published var bossToken: String
    @Published private(set) var config: ConnectionConfig?
    /// True until the first `restore()` completes, so the shell can show a neutral
    /// splash instead of flashing onboarding for an already-configured user.
    @Published private(set) var isRestoring = true

    private let defaults: UserDefaults
    private let keychain: any TokenStoring

    init(
        defaults: UserDefaults = .standard,
        keychain: (any TokenStoring)? = nil
    ) {
        self.defaults = defaults
        self.keychain = keychain ?? KeychainStore(
            service: HiBossStore.keychainService, account: HiBossStore.keychainAccount
        )
        serverAddress = defaults.string(forKey: AppConstants.Storage.serverURL) ?? ""
        bossToken = ""
    }

    var isConfigured: Bool { config != nil }

    /// Loads a persisted token and, if valid, restores the active config.
    func restore() async {
        let keychain = keychain
        let stored = try? await Task.detached(priority: .userInitiated) {
            try keychain.read()
        }.value
        bossToken = stored ?? ""
        if case let .success(config) = makeConnectionConfig(serverAddress: serverAddress, bossToken: bossToken) {
            self.config = config
        }
        isRestoring = false
    }

    /// Validates + persists the entered credentials and verifies them against the server.
    func connect() async -> Result<Void, Error> {
        switch makeConnectionConfig(serverAddress: serverAddress, bossToken: bossToken) {
        case let .failure(error):
            return .failure(error)
        case let .success(candidate):
            do {
                try await HibossAPI(config: candidate).verifyConnection()
            } catch {
                return .failure(error)
            }
            do {
                try keychain.write(candidate.bossToken)
            } catch {
                return .failure(error)
            }
            defaults.set(candidate.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
            config = candidate
            return .success(())
        }
    }

    func signOut() {
        try? keychain.write("")
        bossToken = ""
        config = nil
    }

    func makeAPI() -> HibossAPI? {
        guard let config else { return nil }
        return HibossAPI(config: config, clientSource: "ios")
    }
}
