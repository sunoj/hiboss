// Remote-notification authorization, category/action registration, and handling.
// Exports: PushManager — requests auth, registers the APNs token with the server,
// and turns notification actions (Approve/Reject/Reply) into boss-API replies.
// Dependencies: UserNotifications, UIKit, HibossKit, shared HiBossStore.

import HibossKit
import UIKit
import UserNotifications
import os

private let pushLog = Logger(subsystem: "ai.hiboss.ios", category: "Push")

enum PushCategory {
    static let options = "HIBOSS_OPTIONS"
    static let message = "HIBOSS_MESSAGE"
}

enum PushAction {
    static let approve = "HIBOSS_APPROVE"
    static let reject = "HIBOSS_REJECT"
    static let reply = "HIBOSS_REPLY"
}

@MainActor
final class PushManager: NSObject {
    static let shared = PushManager()

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
    }

    /// Asks for alert/sound/badge permission and, if granted, registers for APNs.
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { pushLog.error("auth error: \(error.localizedDescription)") }
            guard granted else { pushLog.info("notifications not granted"); return }
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Called from the app delegate with the raw APNs token; forwards it to the server.
    func register(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let bundleId = Bundle.main.bundleIdentifier, let api = HiBossStore.bossAPI() else {
            pushLog.info("skipping token registration — not configured")
            return
        }
        Task {
            do {
                try await api.registerDevice(token: hex, bundleId: bundleId, environment: environment)
                pushLog.info("registered device token with server")
            } catch {
                pushLog.error("device registration failed: \(error.localizedDescription)")
            }
        }
    }

    private func optionsCategory() -> UNNotificationCategory {
        let approve = UNNotificationAction(identifier: PushAction.approve, title: "Approve", options: [.foreground])
        let reject = UNNotificationAction(identifier: PushAction.reject, title: "Reject", options: [.destructive])
        let reply = UNTextInputNotificationAction(
            identifier: PushAction.reply, title: "Reply…", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Type a reply"
        )
        return UNNotificationCategory(
            identifier: PushCategory.options, actions: [approve, reject, reply],
            intentIdentifiers: [], options: []
        )
    }

    private func messageCategory() -> UNNotificationCategory {
        let reply = UNTextInputNotificationAction(
            identifier: PushAction.reply, title: "Reply…", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Type a reply"
        )
        return UNNotificationCategory(
            identifier: PushCategory.message, actions: [reply],
            intentIdentifiers: [], options: []
        )
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    // Show banners even while the app is foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
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
        default: choice = nil
        }
        guard let choice, !choice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let api = HiBossStore.bossAPI() {
            _ = try? await api.reply(to: MessageID(rawValue: messageID), with: choice)
            pushLog.info("replied to \(messageID) from notification action")
        }
    }
}
