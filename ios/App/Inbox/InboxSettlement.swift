// Settled-decision lookup: keep an answered card visible and join session replies.
// Exports: DecisionSettlement and InboxStore helpers for cards / threads.
// Dependencies: SwiftUI Text, HibossKit HistoryMessage, SessionGrouping, resolutionSourceLabel.

import HibossKit
import SwiftUI

/// The recorded choice for a decision, plus which surface produced it.
struct DecisionSettlement: Equatable {
    let answer: String
    let source: String?
    /// The server's timeout default, from the reply's `auto_default` marker, never from `source`.
    var isAutoDefault = false

    var sourceLabel: String? { resolutionSourceLabel(source) }

    /// True when the answer came from another boss surface, not this iOS client.
    var answeredElsewhere: Bool {
        guard let source, !isAutoDefault else { return false }
        return source.lowercased() != "ios"
    }

    /// Who produced the answer. A timeout default is never worded as the boss's answer.
    var attribution: Text {
        if isAutoDefault { return Text("Auto-selected when time ran out") }
        if answeredElsewhere, let sourceLabel { return Text("Answered on \(sourceLabel)") }
        return Text("Answered")
    }

    /// The pending card's auto-select glyph, not the checkmark of a choice someone made.
    var symbol: String { isAutoDefault ? "clock.arrow.circlepath" : "checkmark.circle.fill" }
}

extension DecisionSettlement {
    /// The persisted reply's answer, source and automatic marker; nil for an empty reply.
    init?(reply: HistoryMessage) {
        let text = reply.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.init(answer: text, source: reply.metadata?.source,
                  isAutoDefault: reply.metadata?.isAutoDefault == true)
    }

    /// A live stream resolution, until the persisted reply arrives with history.
    init?(resolution: OptionResolution) {
        guard let text = resolution.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        self.init(answer: text, source: resolution.source, isAutoDefault: resolution.isAutoDefault)
    }

    static func fromReply(in history: [HistoryMessage], for id: MessageID) -> DecisionSettlement? {
        history.first(where: { $0.replyTo == id.rawValue }).flatMap(DecisionSettlement.init(reply:))
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
