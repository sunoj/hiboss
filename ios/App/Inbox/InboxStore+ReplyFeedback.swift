// The in-app reply path for every surface that answers a decision (Home, transcript, detail).
// Exports: InboxStore.reply (admitted by DecisionReplyGate) and replyWithFeedback (haptic + note).
// Dependencies: UIKit haptics, DecisionReplyGate, InboxStore.settleReply.

import HibossKit
import UIKit

extension InboxStore {
    func submissionAnswerability(for id: MessageID, verified: DecisionAnswerability,
                                 didVerify: Bool, isDecision: Bool? = nil) -> DecisionAnswerability {
        guard api != nil else { return .checking }
        if withdrawn.contains(id) { return .closed }
        if didVerify && verified != .open { return verified }
        let classification = requiredInputs.first { $0.id == id }?.isDecision
            ?? message(for: id)?.isDecision ?? isDecision
        if classification == false { return .open }
        let current = answerability(for: id)
        guard current == .open else { return current }
        return hasCompleteRequiredInputs ? current : (didVerify ? verified : .checking)
    }

    /// Sends through the shared gate, so a second reply for the same decision from any
    /// surface returns `.busy` without reaching the server.
    @discardableResult
    func reply(_ choice: String, to id: MessageID, isDecision knownDecision: Bool? = nil) async
        -> ReplyResult {
        guard let api else { return .failed }
        guard replying[id] == nil else { return .busy }
        replyFeedback[id] = nil
        let message = message(for: id)
        let classification = requiredInputs.first { $0.id == id }?.isDecision
            ?? message?.isDecision ?? knownDecision
        let state = classification == true ? answerability(for: id) : .open
        guard state == .open else {
            if state == .checking { replyFeedback[id] = state.label }
            return state == .closed ? .alreadyResolved : .failed
        }
        let epoch = requiredEpoch
        let confirmed = hasCompleteRequiredInputs
        let submission = await replyGate.submit(choice, to: id, via: api,
                                                answerability: confirmed ? state : nil,
                                                recheck: { [weak self] id, verified, didVerify in
            self?.submissionAnswerability(for: id, verified: verified, didVerify: didVerify,
                                          isDecision: classification) ?? .checking
        }, onAuthorizationFailure: rejectAuthorization)
        // Signed out or switched account while in flight: report, but touch no new state.
        guard epoch == requiredEpoch else { return ReplyResult(submission) }
        switch submission {
        case .busy:
            break
        case .accepted, .acceptedOn:
            let device: AnsweringDevice?
            if case let .acceptedOn(value) = submission { device = value } else { device = nil }
            settleReply(choice.trimmingCharacters(in: .whitespacesAndNewlines), for: id, answeredBy: device)
            replyConfirmation = String(localized: "Reply sent.")
            refreshHistory()
        case .alreadyResolved:
            settleReply(nil, for: id, closed: true)
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
            return String(localized: "No longer open")
        case .failed:
            if let feedback = replyFeedback[id] { return feedback }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return String(localized: "Couldn't send your reply — check your connection.")
        }
    }
}

extension ReplyResult {
    init(_ submission: DecisionSubmission) {
        switch submission {
        case .accepted, .acceptedOn: self = .sent
        case .alreadyResolved: self = .alreadyResolved
        case .failed: self = .failed
        case .busy: self = .busy
        }
    }
}
