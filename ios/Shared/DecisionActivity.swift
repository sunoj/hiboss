// Shared Live Activity contract + config, compiled into the app and widget.
// Exports: DecisionActivityAttributes and HiBossStore (storage-backed API).
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
    }

    var messageID: String
    var agentName: String
    var meta: String
}

/// Storage keys shared by the app's ConnectionStore and the Live Activity intent.
enum HiBossStore {
    static let keychainService = "ai.hiboss.ios"
    static let keychainAccount = "boss-token"

    /// Rebuilds the boss API from persisted server URL + Keychain token.
    static func bossAPI() -> HibossAPI? {
        let server = UserDefaults.standard.string(forKey: AppConstants.Storage.serverURL) ?? ""
        let token = (try? KeychainStore(service: keychainService, account: keychainAccount).read()) ?? nil
        guard case let .success(config) = makeConnectionConfig(serverAddress: server, bossToken: token ?? "") else {
            return nil
        }
        return HibossAPI(config: config, clientSource: "ios")
    }
}
