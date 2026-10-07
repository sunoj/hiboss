// Read-only connection discovery for the share extension.
// Exports ShareConnection; the app publishes its URL in the App Group.
// Dependencies: Foundation, HibossKit and expanded Info.plist access groups.

import Foundation
import HibossKit

enum ShareConnection {
    static let appGroup = "group.ai.hiboss.app"

    static var sharedAccessGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "SharedKeychainAccessGroup") as? String ?? ""
    }

    static func read() -> ConnectionConfig? {
        let group = sharedAccessGroup
        guard !group.isEmpty, !group.contains("$("),
              let server = UserDefaults(suiteName: appGroup)?.string(forKey: AppConstants.Storage.serverURL),
              let token = try? KeychainStore(service: "ai.hiboss.app", accessGroup: group).read(),
              !token.isEmpty,
              case let .success(config) = makeConnectionConfig(
                serverAddress: server, bossToken: token
              )
        else { return nil }
        return config
    }
}
