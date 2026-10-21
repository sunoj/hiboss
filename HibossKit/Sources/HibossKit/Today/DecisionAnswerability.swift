// The one answerable rule for a decision, shared by every iOS and macOS reply entry point.
// Exports: DecisionAnswerability (checking, open, closed).
// Dependencies: Foundation and MessageID; open IDs come from the server's required-input list.

import Foundation

public enum DecisionAnswerability: Equatable, Sendable {
    case checking, open, closed

    /// Withdrawn wins; until the required-input list loads nothing is answerable yet; after it
    /// loads, only the listed decisions are open.
    public init(id: MessageID, openIDs: Set<MessageID>, loaded: Bool, withdrawn: Set<MessageID> = []) {
        if withdrawn.contains(id) { self = .closed }
        else if !loaded { self = .checking }
        else { self = openIDs.contains(id) ? .open : .closed }
    }
}
