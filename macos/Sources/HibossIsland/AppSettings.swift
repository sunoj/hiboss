// Persists connection and presentation preferences, with tokens in Keychain.
// Exports: AppSettings and OptionPresentationMode.
// Dependencies: HibossKit keychain/config, Foundation UserDefaults, and Combine.

import Combine
import Foundation
import HibossKit

enum OptionPresentationMode: String, CaseIterable, Identifiable, Sendable {
    case island
    case window

    var id: String { rawValue }

    var label: String {
        switch self {
        case .island: L("Island")
        case .window: L("Window")
        }
    }
}

enum OptionDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case island
    case window
    case banner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .island: L("Island")
        case .window: L("Window")
        case .banner: L("Banner")
        }
    }
}

extension OptionDisplayMode {
    init(presentationMode: OptionPresentationMode) {
        switch presentationMode {
        case .island: self = .island
        case .window: self = .window
        }
    }

    var presentationMode: OptionPresentationMode {
        switch self {
        case .island: .island
        case .window: .window
        case .banner: .window
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var serverAddress: String
    @Published var bossToken: String
    @Published var deviceLabel = Host.current().localizedName ?? "Mac"
    @Published private(set) var clientExchangeNotice: String?
    @Published private(set) var activeClientConfig: ConnectionConfig?
    @Published var presentationMode: OptionPresentationMode {
        didSet { defaults.set(presentationMode.rawValue, forKey: AppConstants.Storage.presentationMode) }
    }
    @Published var optionDisplayMode: OptionDisplayMode {
        didSet {
            defaults.set(optionDisplayMode.rawValue, forKey: Self.optionDisplayModeKey)
            presentationMode = optionDisplayMode.presentationMode
        }
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
    @Published var prioritySounds: [MessagePriority: OptionSound] {
        didSet { persistPrioritySounds() }
    }

    private let defaults: UserDefaults
    private let keychain: any TokenStoring
    private let clientsAPI: (ConnectionConfig) -> any BossClientsServing
    private static let optionDisplayModeKey = "hiboss.optionDisplayMode"
    private static let prioritySoundsKey = "hiboss.prioritySounds"

    init(
        defaults: UserDefaults = .standard,
        keychain: any TokenStoring = KeychainStore(),
        clientsAPI: @escaping (ConnectionConfig) -> any BossClientsServing = { HibossAPI(config: $0) }
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.clientsAPI = clientsAPI
        serverAddress = defaults.string(forKey: AppConstants.Storage.serverURL) ?? ""
        bossToken = ""
        let storedPresentationMode = OptionPresentationMode(
            rawValue: defaults.string(forKey: AppConstants.Storage.presentationMode) ?? ""
        ) ?? .island
        presentationMode = storedPresentationMode
        optionDisplayMode = OptionDisplayMode(
            rawValue: defaults.string(forKey: Self.optionDisplayModeKey) ?? ""
        ) ?? OptionDisplayMode(presentationMode: storedPresentationMode)
        showsStatusItem = defaults.object(forKey: AppConstants.Storage.showsStatusItem) == nil
            ? true
            : defaults.bool(forKey: AppConstants.Storage.showsStatusItem)
        playsSound = defaults.object(forKey: AppConstants.Storage.playsSound) == nil
            ? true
            : defaults.bool(forKey: AppConstants.Storage.playsSound)
        alertSound = OptionSound(
            rawValue: defaults.string(forKey: AppConstants.Storage.alertSound) ?? ""
        ) ?? .fallback
        prioritySounds = Self.loadPrioritySounds(from: defaults)
    }

    func loadToken() async {
        let keychain = keychain
        let storedToken = try? await Task.detached(priority: .userInitiated) {
            try keychain.read()
        }.value
        bossToken = storedToken ?? ""
        activeClientConfig = try? connectionConfig().get()
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

    /// Only a changed credential/server is a manual login; routine reconnects retain the token.
    func connect() async -> Result<ConnectionConfig, Error> {
        do {
            let candidate = try connectionConfig().get()
            let api = clientsAPI(candidate)
            let isStoredConnection = try keychain.read() == candidate.bossToken
                && defaults.string(forKey: AppConstants.Storage.serverURL) == candidate.serverURL.absoluteString
            let accepted: ConnectionConfig
            var notice = clientExchangeNotice
            if isStoredConnection {
                try await api.verifyConnection()
                accepted = candidate
            } else {
                let login = try await ManualClientLogin.exchange(
                    config: candidate, kind: .macos, label: deviceLabel, api: api
                )
                accepted = login.config
                notice = login.notice
            }
            try keychain.write(accepted.bossToken)
            defaults.set(accepted.serverURL.absoluteString, forKey: AppConstants.Storage.serverURL)
            bossToken = accepted.bossToken
            clientExchangeNotice = notice
            activeClientConfig = accepted
            return .success(accepted)
        } catch {
            return .failure(error)
        }
    }

    func sound(for priority: MessagePriority) -> OptionSound {
        prioritySounds[priority] ?? Self.defaultPrioritySounds[priority] ?? .fallback
    }

    func activateDeviceToken(_ token: String, replacing current: ConnectionConfig) throws -> ConnectionConfig {
        guard activeClientConfig == current else { throw CancellationError() }
        let accepted = ConnectionConfig(serverURL: current.serverURL, bossToken: token)
        try keychain.write(token)
        bossToken = token
        serverAddress = current.serverURL.absoluteString
        clientExchangeNotice = nil
        activeClientConfig = accepted
        return accepted
    }

    func setSound(_ sound: OptionSound, for priority: MessagePriority) {
        var next = prioritySounds
        next[priority] = sound
        prioritySounds = next
    }

    private func persistPrioritySounds() {
        let raw = prioritySounds.reduce(into: [String: String]()) { values, entry in
            values[entry.key.rawValue] = entry.value.rawValue
        }
        defaults.set(raw, forKey: Self.prioritySoundsKey)
    }

    private static func loadPrioritySounds(
        from defaults: UserDefaults
    ) -> [MessagePriority: OptionSound] {
        guard let raw = defaults.dictionary(forKey: prioritySoundsKey) as? [String: String] else {
            return defaultPrioritySounds
        }
        var sounds = defaultPrioritySounds
        for (priorityValue, soundValue) in raw {
            guard let priority = MessagePriority(rawValue: priorityValue),
                  let sound = OptionSound(rawValue: soundValue) else { continue }
            sounds[priority] = sound
        }
        return sounds
    }

    private static let defaultPrioritySounds: [MessagePriority: OptionSound] = [
        .critical: .sosumi,
        .high: .glass,
        .normal: .pop,
        .low: .none,
    ]
}
