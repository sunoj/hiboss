// Deep-link router: carries a tapped notification's message or join request into the UI.
// Exports: AppRouter.shared and JoinRequestTarget, observed by the shell on launch/tap.
// Dependencies: HibossKit MessageID and PushPanelRequest.

import Combine
import HibossKit

struct JoinRequestTarget: Identifiable, Equatable, Sendable {
    let id: String
}

struct PendingMessageRoute: Equatable, Sendable {
    let messageID: MessageID
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Set when a notification is tapped; the shell routes to this message.
    @Published private(set) var pendingMessage: PendingMessageRoute?
    @Published private(set) var pendingPanel: PushPanelRequest?

    /// Set when a join-request push is tapped; the shell opens its approval sheet.
    @Published private(set) var pendingJoinRequest: JoinRequestTarget?

    var pendingMessageID: MessageID? { pendingMessage?.messageID }

    private init() {}

    func open(panel: PushPanelRequest) {
        pendingPanel = panel
    }

    func finishOpening(_ panel: PushPanelRequest) {
        guard pendingPanel == panel else { return }
        pendingPanel = nil
    }

    func open(messageID: String) {
        let id = MessageID(rawValue: messageID)
        pendingMessage = PendingMessageRoute(messageID: id)
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
