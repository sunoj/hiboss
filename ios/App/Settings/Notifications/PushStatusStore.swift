// Reads and reflects the system notification-authorization state for Settings.
// Exports: PushStatusStore and SettingsNotificationPermission for permission-state testing.
// Dependencies: UserNotifications, UIKit, PushManager.

import SwiftUI
import UIKit
import UserNotifications

protocol SettingsNotificationPermission: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
}

struct SystemSettingsNotificationPermission: SettingsNotificationPermission {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }
}

@MainActor
final class PushStatusStore: ObservableObject {
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var hasLoaded = false
    @Published private(set) var isRequesting = false
    @Published private(set) var failureMessage: String?
    private let permission: any SettingsNotificationPermission
    private let register: @MainActor () async -> Void

    init(permission: any SettingsNotificationPermission = SystemSettingsNotificationPermission(),
         register: @escaping @MainActor () async -> Void = {
             await PushManager.shared.registerIfAuthorized()
         }) {
        self.permission = permission
        self.register = register
    }

    func refresh() async {
        status = await permission.authorizationStatus()
        hasLoaded = true
    }

    /// Prompts for permission when undetermined; the system dialog appears once.
    func request() {
        guard !isRequesting else { return }
        isRequesting = true
        failureMessage = nil
        Task {
            defer { isRequesting = false }
            do {
                _ = try await permission.requestAuthorization()
            } catch {
                failureMessage = error.localizedDescription
            }
            await refresh()
            await register()
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    var label: String {
        guard hasLoaded else { return String(localized: "Checking permission…") }
        return switch status {
        case .authorized: String(localized: "Enabled")
        case .provisional: String(localized: "Delivering quietly")
        case .ephemeral: String(localized: "Temporary permission")
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

    var isWaitingForPermission: Bool { isRequesting && !isEnabled }

    /// True when the app must defer to the system Settings app to change state.
    var mustOpenSystemSettings: Bool { status == .denied }
}
