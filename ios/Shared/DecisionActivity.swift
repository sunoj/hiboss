// Shared Live Activity contract, safe countdown ranges, and storage config.
// Exports: DecisionActivityAttributes, DecisionCompletion, DecisionTimerRange, and HiBossStore.
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
        var content: String?
        /// The choice a reply is sending; the buttons stay disabled until it lands.
        var submitting: String?
        var submissionProgressVisible: Bool?
        var submissionIsSlow: Bool?
        var replyFailed: Bool?
        /// How the decision settled; nil while it is still open.
        var completion: DecisionCompletion?
    }

    var messageID: String
    var project: String
    var agentName: String
    var meta: String
}

/// The recorded outcome shown when a decision's Live Activity ends.
enum DecisionCompletion: Codable, Hashable {
    /// This device's reply was recorded.
    case answered(String)
    /// The server's timeout default won: its reply carries `auto_default: true`.
    case autoSelected(String)
    /// Another surface's answer won; nil when the recorded reply could not be read.
    case answeredElsewhere(String?)

    /// The winning reply from message detail, attributed by the automatic marker.
    static func recorded(in detail: MessageDetail?) -> DecisionCompletion {
        guard let reply = detail?.replies.first else { return .answeredElsewhere(nil) }
        let answer = reply.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return reply.metadata?.isAutoDefault == true ? .autoSelected(answer) : .answeredElsewhere(answer)
    }
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

    /// What notification actions and the Live Activity intent reply through. Only tests
    /// assign it, to hold replies; the app always uses the persisted connection.
    @MainActor static var replyAPI: () -> (any BossServing)? = { bossAPI() }

    /// Rebuilds the boss API from persisted server URL + Keychain token.
    static func bossAPI() -> HibossAPI? {
        let server = UserDefaults.standard.string(forKey: AppConstants.Storage.serverURL) ?? ""
        let token = (try? KeychainStore(service: keychainService, account: keychainAccount).read()) ?? nil
        guard case let .success(config) = makeConnectionConfig(serverAddress: server, bossToken: token ?? "")
        else {
            return nil
        }
        let signer = try? KeychainMessageSignerStore(
            service: keychainService,
            account: signingKeychainAccount
        ).read()
        return HibossAPI(config: config, messageSigner: signer)
    }
}
