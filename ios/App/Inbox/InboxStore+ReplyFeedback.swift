// One reply path for every surface that answers a decision (Home, session transcript).
// Exports: InboxStore.replyWithFeedback — sends, plays the haptic, returns a note to show.
// Dependencies: UIKit haptics, InboxStore.reply.

import HibossKit
import UIKit

extension InboxStore {
    /// Sends the choice and plays the matching haptic; returns a message for the boss
    /// when the reply did not land as their answer, or nil when it did.
    /// A second tap while the first reply is in flight is ignored rather than sent as a
    /// competing answer, which the server would report as "answered elsewhere".
    func replyWithFeedback(_ choice: String, to id: MessageID) async -> String? {
        guard replying[id] == nil else { return nil }
        replying[id] = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { replying[id] = nil }
        switch await reply(choice, to: id) {
        case .sent:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return nil
        case .alreadyResolved:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return String(localized: "That decision was already answered elsewhere.")
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return String(localized: "Couldn't send your reply — check your connection.")
        }
    }
}
