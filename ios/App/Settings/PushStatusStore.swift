// Reads and reflects the system notification-authorization state for Settings.
// Exports: PushStatusStore — observable auth status with request / open-settings.
// Dependencies: UserNotifications, UIKit, PushManager.

import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class PushStatusStore: ObservableObject {
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Prompts for permission when undetermined; the system dialog appears once.
    func request() {
        PushManager.shared.requestAuthorization()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    var label: String {
        switch status {
        case .authorized, .provisional, .ephemeral: String(localized: "Enabled")
        case .denied: String(localized: "Denied")
        case .notDetermined: String(localized: "Not set up")
        @unknown default: String(localized: "Unknown")
        }
    }

    var isEnabled: Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// True when the app must defer to the system Settings app to change state.
    var mustOpenSystemSettings: Bool { status == .denied }
}
