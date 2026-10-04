// The in-app reply path for every surface that answers a decision (Home, transcript, detail).
// Exports: InboxStore.reply (admitted by DecisionReplyGate) and replyWithFeedback (haptic + note).
// Dependencies: UIKit haptics, DecisionReplyGate, InboxStore.settleReply.

import HibossKit
import UIKit

extension InboxStore {
    /// Sends through the shared gate, so a second reply for the same decision from any
    /// surface returns `.busy` without reaching the server.
    @discardableResult
    func reply(_ choice: String, to id: MessageID) async -> ReplyResult {
        guard let api else { return .failed }
        let epoch = requiredEpoch
        let submission = await replyGate.submit(choice, to: id, via: api)
        // Signed out or switched account while in flight: report, but touch no new state.
        guard epoch == requiredEpoch else { return ReplyResult(submission) }
        switch submission {
        case .busy:
            break
        case .accepted:
            settleReply(choice.trimmingCharacters(in: .whitespacesAndNewlines), for: id)
            refreshHistory()
        case .alreadyResolved:
            settleReply(nil, for: id)
            refreshHistory()
        case let .failed(reason):
            settleReply(nil, for: id, error: reason)
        }
        return ReplyResult(submission)
    }

    /// Sends the choice and plays the matching haptic; returns a message for the boss
    /// when the reply did not land as their answer, or nil when it did. A tap while a
    /// reply is in flight is ignored rather than sent as a competing answer.
    func replyWithFeedback(_ choice: String, to id: MessageID) async -> String? {
        switch await reply(choice, to: id) {
        case .busy:
            return nil
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

extension ReplyResult {
    init(_ submission: DecisionSubmission) {
        switch submission {
        case .accepted: self = .sent
        case .alreadyResolved: self = .alreadyResolved
        case .failed: self = .failed
        case .busy: self = .busy
        }
    }
}
