// Central constants for API behavior, persistence keys, and island geometry.
// Exports: AppConstants namespaces used throughout the app.
// Dependencies: Foundation Duration and CoreGraphics dimensions.

import Foundation

enum AppConstants {
    enum API {
        static let reconnectDelay: Duration = .seconds(2)
        static let requestTimeout: TimeInterval = 15
        static let historyLimit = 100
    }

    enum Island {
        static let width: CGFloat = 420
        static let collapsedWidth: CGFloat = 184
        static let collapsedHeight: CGFloat = 36
        static let animationDuration: TimeInterval = 0.28
    }

    enum Storage {
        static let serverURL = "hiboss.serverURL"
        static let presentationMode = "hiboss.presentationMode"
        static let showsStatusItem = "hiboss.showsStatusItem"
        static let playsSound = "hiboss.playsSound"
        static let alertSound = "hiboss.alertSound"
        static let keychainService = "ai.hiboss.island.stable"
        static let keychainAccount = "boss-token"
    }
}
