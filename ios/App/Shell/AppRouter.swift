// Deep-link router: carries a tapped notification's message into the UI.
// Exports: AppRouter.shared, observed by the shell to navigate on launch/tap.
// Dependencies: HibossKit MessageID.

import Combine
import HibossKit

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Set when a notification is tapped; the shell routes to this message.
    @Published var pendingMessageID: MessageID?

    private init() {}

    func open(messageID: String) {
        pendingMessageID = MessageID(rawValue: messageID)
    }
}
