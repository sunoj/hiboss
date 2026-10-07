// Prevents an empty cached attention queue from claiming all clear while offline.
// Exports: HomeConnectionStatus.notice; connected still requires complete fetch coverage.
// Dependencies: Foundation localization and HibossKit ConnectionState.

import Foundation
import HibossKit

enum HomeConnectionStatus {
    static func notice(for state: ConnectionState) -> String? {
        switch state {
        case .connected: nil
        case .connecting: String(localized: "Connecting…")
        case .disconnected: String(localized: "Not connected. Pull to refresh or reconnect in Settings.")
        case .failed: String(localized: "Connection failed. Pull to refresh or reconnect in Settings.")
        }
    }
}
