// Settled-decision lookup: keep an answered card visible and join session replies.
// Exports: DecisionSettlement and InboxStore helpers for cards / threads.
// Dependencies: HibossKit HistoryMessage, SessionGrouping, resolutionSourceLabel.

import Foundation
import HibossKit

/// The recorded choice for a decision, plus which surface produced it.
struct DecisionSettlement: Equatable {
    let answer: String
    let source: String?

    var sourceLabel: String? { resolutionSourceLabel(source) }

    /// True when the answer did not come from this iOS client.
    var answeredElsewhere: Bool {
        guard let source else { return false }
        return source.lowercased() != "ios"
    }

    static func fromReply(in history: [HistoryMessage], for id: MessageID) -> DecisionSettlement? {
        guard let reply = history.first(where: { $0.replyTo == id.rawValue }) else { return nil }
        let text = reply.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return DecisionSettlement(answer: text, source: reply.metadata?.source)
    }
}

extension InboxStore {
    /// Answered decision cards kept in the queue so the choice stays visible.
    var settledCards: [HistoryMessage] {
        let live = Set(pending.map(\.id))
        return history
            .filter { message in
                guard !live.contains(message.id) else { return false }
                if settledIDs.contains(message.id) { return true }
                return message.isDecision && !message.isPendingDecision
            }
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
    }

    /// Newest settled message per session, excluding live/settled cards.
    var settledHistory: [HistoryMessage] {
        let hidden = Set(pending.map(\.id)).union(settledCards.map(\.id))
        var seen = Set<String>()
        return history
            .filter { !hidden.contains($0.id) }
            .sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            .filter { seen.insert(SessionGrouping.sessionKey(for: $0)).inserted }
    }

    /// Chosen answer for a decision: local/stream first, then the persisted reply.
    func settlement(for id: MessageID) -> DecisionSettlement? {
        if let local = localResolutions[id] { return local }
        return DecisionSettlement.fromReply(in: history, for: id)
    }

    /// Session thread: messages keyed to the session, plus replies whose parent is.
    func messages(inSession routeID: String) -> [HistoryMessage] {
        let primary = history.filter { SessionGrouping.sessionKey(for: $0) == routeID }
        let ids = Set(primary.map(\.id.rawValue))
        let extras = history.filter { message in
            guard let parent = message.replyTo, ids.contains(parent) else { return false }
            return SessionGrouping.sessionKey(for: message) != routeID
        }
        return (primary + extras).sorted {
            ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast)
        }
    }
}
