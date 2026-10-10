// Applies the answerable rule to every macOS decision and reply entry point.
// Exports: AnswerableDecisions and DecisionAnswerState, derived from required-input coverage.
// Dependencies: HibossKit history, thread outcomes, and the shared Today projection.

import Foundation
import HibossKit

enum DecisionAnswerState {
    case checking, open, closed
}

struct AnswerableDecisions {
    let isLoaded: Bool
    let openIDs: Set<MessageID>
    var closedIDs: Set<MessageID> = []

    static let loading = Self(isLoaded: false, openIDs: [])

    func state(for id: MessageID) -> DecisionAnswerState {
        if closedIDs.contains(id) { return .closed }
        guard isLoaded else { return .checking }
        return openIDs.contains(id) ? .open : .closed
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
