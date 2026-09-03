// Remote-notification authorization, category/action registration, and handling.
// Exports: PushManager — requests auth, registers the APNs token with the server,
// and turns notification actions (Approve/Reject/Reply) into boss-API replies.
// Dependencies: UserNotifications, UIKit, HibossKit, shared HiBossStore.

import HibossKit
import UIKit
import UserNotifications
import os

private let pushLog = Logger(subsystem: "ai.hiboss.app", category: "Push")

enum PushCategory {
    static let options = "HIBOSS_OPTIONS"
    static let message = "HIBOSS_MESSAGE"
}

enum PushAction {
    static let approve = "HIBOSS_APPROVE"
    static let reject = "HIBOSS_REJECT"
    static let reply = "HIBOSS_REPLY"
}

/// Server-side device-registration state, surfaced in Settings so "Push:
/// Enabled" (OS auth) can't imply the device is actually reachable.
enum DeviceRegistration: Equatable {
    case idle, registering, registered, failed(String)
}

@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published private(set) var registration: DeviceRegistration = .idle

    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Wires the notification center delegate and registers actionable categories.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([optionsCategory(), messageCategory()])
        Task { await registerIfAuthorized() }
    }

    /// Re-registers for APNs on every launch when already authorized, so a
    /// reinstall / restore / OS token rotation refreshes the server's token.
    /// The grant-time path in `requestAuthorization` only covers first consent.
    func registerIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            registration = .idle
            return
        }
        registration = .registering
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Prompts for permission only when undetermined. An already-authorized user
    /// is re-registered by `configure()`'s `registerIfAuthorized`, so the connect
    /// path must not re-`requestAuthorization` — that double-registered every
    /// launch and flickered the Settings status Registered→Registering→Registered.
    func promptIfNeeded() {
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .notDetermined { requestAuthorization() }
        }
    }

    /// Asks for alert/sound/badge permission and, if granted, registers for APNs.
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { pushLog.error("auth error: \(error.localizedDescription)") }
            guard granted else { pushLog.info("notifications not granted"); return }
            Task { @MainActor in
                self.registration = .registering
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// APNs failed to hand us a token (no network, provisioning, etc.).
    func registrationFailed(_ error: Error) {
        registration = .failed(error.localizedDescription)
    }

    /// Called from the app delegate with the raw APNs token; forwards it to the server.
    func register(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let bundleId = Bundle.main.bundleIdentifier, let api = HiBossStore.bossAPI() else {
            pushLog.info("skipping token registration — not configured")
            registration = .failed(String(localized: "Not connected to a server"))
            return
        }
        registration = .registering
        Task {
            do {
                try await api.registerDevice(token: hex, bundleId: bundleId, environment: environment)
                pushLog.info("registered device token with server")
                registration = .registered
            } catch {
                pushLog.error("device registration failed: \(error.localizedDescription)")
                registration = .failed(error.localizedDescription)
            }
        }
    }

    private func optionsCategory() -> UNNotificationCategory {
        let approve = UNNotificationAction(identifier: PushAction.approve, title: String(localized: "Approve"), options: [.foreground])
        let reject = UNNotificationAction(identifier: PushAction.reject, title: String(localized: "Reject"), options: [.destructive])
        let reply = UNTextInputNotificationAction(
            identifier: PushAction.reply, title: String(localized: "Reply…"), options: [],
            textInputButtonTitle: String(localized: "Send"), textInputPlaceholder: String(localized: "Type a reply")
        )
        return UNNotificationCategory(
            identifier: PushCategory.options, actions: [approve, reject, reply],
            intentIdentifiers: [], options: []
        )
    }

    private func messageCategory() -> UNNotificationCategory {
        let reply = UNTextInputNotificationAction(
            identifier: PushAction.reply, title: String(localized: "Reply…"), options: [],
            textInputButtonTitle: String(localized: "Send"), textInputPlaceholder: String(localized: "Type a reply")
        )
        return UNNotificationCategory(
            identifier: PushCategory.message, actions: [reply],
            intentIdentifiers: [], options: []
        )
    }
}

extension PushManager: @preconcurrency UNUserNotificationCenterDelegate {
    // Show banners even while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let messageID = info["messageId"] as? String else { return }
        let options = info["options"] as? [String] ?? []

        let choice: String?
        switch response.actionIdentifier {
        case PushAction.approve: choice = options.first
        case PushAction.reject: choice = options.count > 1 ? options[1] : nil
        case PushAction.reply: choice = (response as? UNTextInputNotificationResponse)?.userText
        case UNNotificationDefaultActionIdentifier:
            // A plain tap opens the message's full-text detail.
            AppRouter.shared.open(messageID: messageID)
            return
        default: choice = nil
        }
        guard let choice, !choice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let api = HiBossStore.bossAPI() {
            _ = try? await api.reply(to: MessageID(rawValue: messageID), with: choice)
            pushLog.info("replied to \(messageID) from notification action")
        }
    }
}
