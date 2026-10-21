// Applies the answerable rule to every macOS decision and reply entry point.
// Exports: AnswerableDecisions, applying HibossKit's DecisionAnswerability to required inputs.
// Dependencies: HibossKit history, thread outcomes, and the shared Today projection.

import Foundation
import HibossKit

struct AnswerableDecisions {
    let isLoaded: Bool
    let openIDs: Set<MessageID>
    var closedIDs: Set<MessageID> = []

    static let loading = Self(isLoaded: false, openIDs: [])

    func state(for id: MessageID) -> DecisionAnswerability {
        DecisionAnswerability(id: id, openIDs: openIDs, loaded: isLoaded, withdrawn: closedIDs)
    }

    func permitsReply(to message: HistoryMessage) -> Bool {
        isLoaded && message.direction == "agent_to_boss"
            && (!message.isDecision || state(for: message.id) == .open)
    }

    func outcome(for thread: MessageThread, at now: Date) -> ThreadOutcome {
        let recorded = thread.outcome(at: now)
        guard thread.message.isDecision, recorded == .open || recorded == .none else {
            return recorded
        }
        return state(for: thread.id) == .open ? .open : .none
    }
}
