// Native notification delivery behind an entitlement-free testing boundary.
// Exports: MessageNotificationCenter, MessageNotice, and SystemMessageNotificationCenter.
// Dependencies: UserNotifications, AppKit, and HibossKit message identifiers.

import AppKit
import HibossKit
import UserNotifications

enum MessageNotificationAuthorization: Equatable {
    case notDetermined, denied, authorized, provisional, unknown

    var label: String {
        switch self {
        case .notDetermined: L("Not requested")
        case .denied: L("Denied")
        case .authorized: L("Allowed")
        case .provisional: L("Deliver quietly")
        case .unknown: L("Unknown")
        }
    }
}

struct MessageNotice: Equatable, Sendable {
    static let bodyLimit = 240
    let messageID: MessageID
    let title: String
    let body: String
    let threadIdentifier: String
    var sound = true
    var level: PushLevel = .active

    init(message: HistoryMessage, alert: MessageAlert? = nil) {
        messageID = message.id
        if let alert {
            sound = alert.sound
            level = alert.level
        }
        let agent = Self.cleaned(message.agentName) ?? L("Agent")
        title = Self.cleaned(message.sessionLabel).map { "\(agent) · \($0)" } ?? agent
        let text = message.body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        body = text.count > Self.bodyLimit ? String(text.prefix(Self.bodyLimit - 1)) + "…" : text
        threadIdentifier = Self.cleaned(message.sessionId) ?? ""
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}

extension PushLevel {
    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .passive: .passive
        case .active: .active
        case .timeSensitive: .timeSensitive
        }
    }
}

@MainActor
protocol MessageNotificationCenter: AnyObject {
    var isEnabled: Bool { get set }
    func authorization() async -> MessageNotificationAuthorization
    func requestAuthorization() async throws
    func post(_ notice: MessageNotice) async throws
}

@MainActor
final class SystemMessageNotificationCenter: NSObject, MessageNotificationCenter {
    var isEnabled = true
    var onOpen: ((MessageID) -> Void)?
    var onOpenJoinRequest: ((String) -> Void)?
    var onOpenQuestionnaire: ((String) -> Void)?
    // Delay accessing current() until app launch; SwiftPM tests have no app bundle.
    private lazy var center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
    }

    func authorization() async -> MessageNotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        @unknown default: .unknown
        }
    }

    func requestAuthorization() async throws {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ notice: MessageNotice) async throws {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.threadIdentifier = notice.threadIdentifier
        content.sound = notice.sound ? .default : nil
        content.interruptionLevel = notice.level.interruptionLevel
        content.userInfo = ["messageID": notice.messageID.rawValue]
        try await center.add(UNNotificationRequest(
            identifier: notice.messageID.rawValue, content: content, trigger: nil
        ))
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

extension SystemMessageNotificationCenter: UNUserNotificationCenterDelegate {
    /// Foreground presentation follows the notice's tier: a passive notice is listed silently.
    nonisolated static func presentation(passive: Bool, sound: Bool) -> UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = passive ? [.list] : [.banner, .list]
        if sound { options.insert(.sound) }
        return options
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Join requests are an admin security prompt, not a message; the message toggle does not mute them.
        let isJoinRequest = notification.request.content.userInfo[JoinRequestNotice.userInfoKey] is String
        let content = notification.request.content
        let tier = Self.presentation(passive: content.interruptionLevel == .passive, sound: content.sound != nil)
        return await MainActor.run { isEnabled || isJoinRequest ? tier : [] }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let id = info["messageID"] as? String
        let joinRequestID = info[JoinRequestNotice.userInfoKey] as? String
        let panelID = info[QuestionnaireNotice.userInfoKey] as? String
        let isOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        await MainActor.run {
            guard isOpen else { return }
            if let joinRequestID {
                onOpenJoinRequest?(joinRequestID)
            } else if let panelID {
                onOpenQuestionnaire?(panelID)
            } else if let id {
                onOpen?(MessageID(rawValue: id))
            }
        }
    }
}
