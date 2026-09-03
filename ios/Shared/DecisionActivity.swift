// Shared Live Activity contract, safe countdown ranges, and storage config.
// Exports: DecisionActivityAttributes, DecisionTimerRange, and HiBossStore.
// Dependencies: ActivityKit, HibossKit. iOS-only (not part of HibossKit).

import ActivityKit
import Foundation
import HibossKit

/// The ActivityKit attributes for a pending decision, matched by type name
/// across the app and widget extension processes.
struct DecisionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var body: String
        var options: [String]
        var priority: String
        var deadline: Date?
        var resolved: Bool
        var content: String?
    }

    var messageID: String
    var project: String
    var agentName: String
    var meta: String
}

/// ClosedRange traps when its lower bound is later than its upper bound. Widget
/// rendering can occur after a decision expires, so only create forward ranges.
enum DecisionTimerRange {
    static func active(until deadline: Date?, now: Date = Date()) -> ClosedRange<Date>? {
        guard let deadline, deadline > now else { return nil }
        return now...deadline
    }
}

/// Storage keys shared by the app's ConnectionStore and the Live Activity intent.
enum HiBossStore {
    static let keychainService = "ai.hiboss.app"
    static let keychainAccount = "boss-token"
    static let signingKeychainAccount = "boss-message-signer"

    /// Rebuilds the boss API from persisted server URL + Keychain token.
    static func bossAPI() -> HibossAPI? {
        let server = UserDefaults.standard.string(forKey: AppConstants.Storage.serverURL) ?? ""
        let token = (try? KeychainStore(service: keychainService, account: keychainAccount).read()) ?? nil
        guard case let .success(config) = makeConnectionConfig(serverAddress: server, bossToken: token ?? "") else {
            return nil
        }
        let signer = try? KeychainMessageSignerStore(
            service: keychainService,
            account: signingKeychainAccount
        ).read()
        return HibossAPI(config: config, messageSigner: signer)
    }
}
