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
    private static let optionDisplayModeKey = "hiboss.optionDisplayMode"
    private static let prioritySoundsKey = "hiboss.prioritySounds"

    init(
        defaults: UserDefaults = .standard,
        keychain: any TokenStoring = KeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain
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

    func sound(for priority: MessagePriority) -> OptionSound {
        prioritySounds[priority] ?? Self.defaultPrioritySounds[priority] ?? .fallback
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
