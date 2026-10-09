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

    static let loading = Self(isLoaded: false, openIDs: [])

    static func isDecision(_ message: HistoryMessage) -> Bool {
        !message.options.isEmpty || message.defaultOption != nil || message.mode == "blocking"
    }

    func state(for id: MessageID) -> DecisionAnswerState {
        guard isLoaded else { return .checking }
        return openIDs.contains(id) ? .open : .closed
    }

    func permitsReply(to message: HistoryMessage) -> Bool {
        isLoaded && message.direction == "agent_to_boss"
            && (!Self.isDecision(message) || state(for: message.id) == .open)
    }

    func outcome(for thread: MessageThread, at now: Date) -> ThreadOutcome {
        let recorded = thread.outcome(at: now)
        guard Self.isDecision(thread.message), recorded == .open || recorded == .none else {
            return recorded
        }
        return state(for: thread.id) == .open ? .open : .none
    }
}
