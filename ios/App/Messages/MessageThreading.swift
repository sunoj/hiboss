// Messages list model: folds boss replies into the message they answer and picks one row badge.
// Exports: MessageThreading (list items) and MessageRowBadge (the single badge a row may carry).
// Dependencies: HibossKit HistoryMessage, MessageDisplay helpers, Theme tokens.

import HibossKit
import SwiftUI

enum MessageThreading {
    enum Item: Identifiable, Equatable {
        /// An agent-authored message plus the boss reply that answers it, if any.
        case agent(HistoryMessage, reply: HistoryMessage?)
        /// A boss-authored message whose parent is not in the list.
        case boss(HistoryMessage)

        var id: MessageID { message.id }

        var message: HistoryMessage {
            switch self {
            case let .agent(message, _), let .boss(message): message
            }
        }
    }

    /// Keeps the input order. A boss reply whose parent is in the list becomes that
    /// parent's `reply` (the newest one wins when there are several) and emits no row.
    /// Authorship is read from `direction` only: boss replies carry the agent's name.
    static func items(from history: [HistoryMessage]) -> [Item] {
        let ids = Set(history.map(\.id.rawValue))
        var replies: [String: HistoryMessage] = [:]
        for message in history where isBoss(message) {
            guard let parent = message.replyTo, ids.contains(parent) else { continue }
            if let current = replies[parent], !isNewer(message, than: current) { continue }
            replies[parent] = message
        }
        return history.compactMap { message in
            if isBoss(message) {
                if let parent = message.replyTo, ids.contains(parent) { return nil }
                return .boss(message)
            }
            return .agent(message, reply: replies[message.id.rawValue])
        }
    }

    /// The answer a row may attribute to the boss. An auto-decided message shows its
    /// "Auto-decided" badge instead: a server default is not the boss's choice.
    static func bossAnswer(for message: HistoryMessage, answer: String?) -> String? {
        guard message.metadata?.isExpired != true else { return nil }
        let text = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    static func isBoss(_ message: HistoryMessage) -> Bool {
        message.direction == "boss_to_agent"
    }

    private static func isNewer(_ lhs: HistoryMessage, than rhs: HistoryMessage) -> Bool {
        (lhs.createdDate ?? .distantPast) > (rhs.createdDate ?? .distantPast)
    }
}

/// The one short text badge a Messages row may show; everything else lives in the detail.
enum MessageRowBadge: Equatable {
    case decisionNeeded
    case autoDecided
    case expired
    case critical
    case high

    /// Precedence: an open decision, then an expiry outcome, then urgent priority.
    static func badge(for message: HistoryMessage) -> MessageRowBadge? {
        if message.isPendingDecision { return .decisionNeeded }
        if message.metadata?.isExpired == true { return .autoDecided }
        if message.status == "expired" { return .expired }
        switch message.priorityValue {
        case .critical: return .critical
        case .high: return .high
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .decisionNeeded: String(localized: "Decision needed")
        case .autoDecided: String(localized: "Auto-decided")
        case .expired: String(localized: "Expired")
        case .critical: String(localized: "Critical")
        case .high: String(localized: "High priority")
        }
    }

    var tint: Color {
        switch self {
        case .decisionNeeded: Theme.accent
        case .autoDecided, .expired: Theme.ink2
        case .critical: Theme.negative
        case .high: Theme.warn
        }
    }
}
