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
    private let signerStore: any MessageSignerStoring
    private let pairingRedeemer: PairingRedeemer
    private var messageSigner: SecureEnclaveMessageSigner?

    init(
        defaults: UserDefaults = .standard,
        keychain: (any TokenStoring)? = nil,
        signerStore: (any MessageSignerStoring)? = nil,
        pairingRedeemer: PairingRedeemer = PairingRedeemer()
    ) {
        self.defaults = defaults
        self.keychain = keychain ?? KeychainStore(
            service: HiBossStore.keychainService, account: HiBossStore.keychainAccount
        )
        self.signerStore = signerStore ?? KeychainMessageSignerStore(
            service: HiBossStore.keychainService,
            account: HiBossStore.signingKeychainAccount
        )
        self.pairingRedeemer = pairingRedeemer
        serverAddress = defaults.string(forKey: AppConstants.Storage.serverURL) ?? ""
        bossToken = ""
    }

    var isConfigured: Bool { config != nil }

    /// Loads a persisted token and, if valid, restores the active config.
    func restore() async {
        let keychain = keychain
        let signerStore = signerStore
        let stored = await Task.detached(priority: .userInitiated) {
            (token: try? keychain.read(), signer: try? signerStore.read())
        }.value
        defer { isRestoring = false }

        let storedToken = stored.token ?? ""
        guard case let .success(restoredConfig) = makeConnectionConfig(
            serverAddress: serverAddress,
            bossToken: storedToken
        ) else {
            bossToken = ""
            messageSigner = nil
            config = nil
            return
        }

        bossToken = storedToken
        messageSigner = stored.signer
        config = restoredConfig
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
                let replacesToken = try keychain.read() != candidate.bossToken
                try keychain.write(candidate.bossToken)
                if replacesToken {
                    try signerStore.delete()
                    messageSigner = nil
                }
            } catch {
                return .failure(error)
            }
            defaults.set(candidate.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
            config = candidate
            return .success(())
        }
    }

    /// Redeems a Mac-generated pairing code and persists the resulting connection.
    func pair(payload: PairingPayload, deviceLabel: String) async -> Result<Void, Error> {
        do {
            let redemption = try await pairingRedeemer.redeem(
                payload: payload,
                deviceLabel: deviceLabel
            )
            guard case let .success(candidate) = makeConnectionConfig(
                serverAddress: payload.serverURL.absoluteString,
                bossToken: redemption.token
            ) else {
                return .failure(SettingsError.invalidServerURL)
            }
            try signerStore.write(redemption.signer)
            do {
                try keychain.write(candidate.bossToken)
            } catch {
                try? signerStore.delete()
                throw error
            }
            defaults.set(candidate.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
            serverAddress = candidate.serverURL.absoluteString
            bossToken = candidate.bossToken
            messageSigner = redemption.signer
            config = candidate
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func signOut() {
        try? keychain.write("")
        try? signerStore.delete()
        bossToken = ""
        messageSigner = nil
        config = nil
    }

    func makeAPI() -> HibossAPI? {
        guard let config else { return nil }
        return HibossAPI(config: config, messageSigner: messageSigner)
    }
}
