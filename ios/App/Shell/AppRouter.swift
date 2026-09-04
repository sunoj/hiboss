// Deep-link router: carries a tapped notification's message into the UI.
// Exports: AppRouter.shared, observed by the shell to navigate on launch/tap.
// Dependencies: HibossKit MessageID and push cache values.

import Combine
import HibossKit

struct PendingMessageRoute: Equatable, Sendable {
    let messageID: MessageID
    let cachedMessage: PushCachedMessage?
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Set when a notification is tapped; the shell routes to this message.
    @Published private(set) var pendingMessage: PendingMessageRoute?

    var pendingMessageID: MessageID? { pendingMessage?.messageID }

    private init() {}

    func open(messageID: String, cachedMessage: PushCachedMessage? = nil) {
        let id = MessageID(rawValue: messageID)
        let matchingCache = cachedMessage?.detail.message.id == id ? cachedMessage : nil
        pendingMessage = PendingMessageRoute(messageID: id, cachedMessage: matchingCache)
    }

    func finishOpening(_ messageID: MessageID) {
        guard pendingMessage?.messageID == messageID else { return }
        pendingMessage = nil
    }
}
