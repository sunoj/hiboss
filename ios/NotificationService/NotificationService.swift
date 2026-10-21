// Notification Service Extension: decrypts relay pushes with this install's push key.
// Exports: NotificationService (NSExtensionPrincipalClass).
// Dependencies: UserNotifications, RelayNotificationContent, KeychainRelayCredentialStore.

import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var original: UNNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        original = request.content
        let key = (try? KeychainRelayCredentialStore().read())
            .flatMap { Base64URL.decode($0.pushKey) }
        deliver(RelayNotificationContent.rewrite(request.content, pushKey: key) ?? request.content)
    }

    /// Out of time: the untouched generic alert is always a valid fallback.
    override func serviceExtensionTimeWillExpire() {
        if let original { deliver(original) }
    }

    private func deliver(_ content: UNNotificationContent) {
        let handler = contentHandler
        contentHandler = nil
        handler?(content)
    }
}
