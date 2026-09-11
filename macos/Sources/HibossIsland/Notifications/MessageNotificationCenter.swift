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

    init(message: HistoryMessage) {
        messageID = message.id
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
        content.sound = .default
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
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            isEnabled ? [.banner, .list, .sound] : []
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["messageID"] as? String
        let isOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        await MainActor.run {
            if isOpen, let id { onOpen?(MessageID(rawValue: id)) }
        }
    }
}
