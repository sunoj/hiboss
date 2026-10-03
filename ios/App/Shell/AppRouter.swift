// Deep-link router: carries a tapped notification's message or join request into the UI.
// Exports: AppRouter.shared and JoinRequestTarget, observed by the shell on launch/tap.
// Dependencies: HibossKit MessageID and push cache values.

import Combine
import HibossKit

struct JoinRequestTarget: Identifiable, Equatable, Sendable {
    let id: String
}

struct PendingMessageRoute: Equatable, Sendable {
    let messageID: MessageID
    let cachedMessage: PushCachedMessage?
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Set when a notification is tapped; the shell routes to this message.
    @Published private(set) var pendingMessage: PendingMessageRoute?

    /// Set when a join-request push is tapped; the shell opens its approval sheet.
    @Published private(set) var pendingJoinRequest: JoinRequestTarget?

    var pendingMessageID: MessageID? { pendingMessage?.messageID }

    private init() {}

    func open(messageID: String, cachedMessage: PushCachedMessage? = nil) {
        let id = MessageID(rawValue: messageID)
        let matchingCache = cachedMessage?.detail.message.id == id ? cachedMessage : nil
        pendingMessage = PendingMessageRoute(messageID: id, cachedMessage: matchingCache)
    }

    func openJoinRequest(id: String) {
        pendingJoinRequest = JoinRequestTarget(id: id)
    }

    /// Hands the pending join request to the caller exactly once.
    func takeJoinRequest() -> JoinRequestTarget? {
        defer { pendingJoinRequest = nil }
        return pendingJoinRequest
    }

    func finishOpening(_ messageID: MessageID) {
        guard pendingMessage?.messageID == messageID else { return }
        pendingMessage = nil
    }
}
