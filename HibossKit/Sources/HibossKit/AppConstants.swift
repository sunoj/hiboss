// Central constants for API behavior, shared persistence keys, and island geometry.
// Exports: AppConstants namespaces used across the native clients.
// Dependencies: Foundation Duration, TimeInterval, and CoreGraphics dimensions.

import Foundation

public enum AppConstants {
    public enum API {
        public static let reconnectDelay: Duration = .seconds(2)
        public static let requestTimeout: TimeInterval = 15
        public static let notificationMessageTimeout: TimeInterval = 4
        public static let historyLimit = 100
        public static let notificationReadinessChecks = 20
        public static let notificationReadinessDelay = Duration.milliseconds(50)
        /// Max events held in the session transcript render window.
        public static let sessionStreamWindow = 300
        /// Coalesce bursty SSE appends before publishing to SwiftUI.
        public static let sessionStreamBatchMilliseconds: UInt64 = 50
    }

    public enum Island {
        public static let width: CGFloat = 420
        public static let collapsedWidth: CGFloat = 184
        public static let collapsedHeight: CGFloat = 36
        public static let animationDuration: TimeInterval = 0.28
    }

    public enum Storage {
        public static let serverURL = "hiboss.serverURL"
        public static let presentationMode = "hiboss.presentationMode"
        public static let showsStatusItem = "hiboss.showsStatusItem"
        public static let playsSound = "hiboss.playsSound"
        public static let alertSound = "hiboss.alertSound"
        public static let keychainService = "ai.hiboss.island.stable"
        public static let keychainAccount = "boss-token"
        public static let signingKeychainAccount = "boss-message-signer"
    }
}
