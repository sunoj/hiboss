// Defines overview destinations and derives tile counts from the exact destination messages.
// Exports: OverviewCategory, OverviewDestination, OverviewSnapshot.
// Dependencies: HibossKit history/session models and AttentionRanking.

import Foundation
import HibossKit

enum OverviewCategory: String, CaseIterable, Identifiable, Sendable {
    case needsYou, automatic, waiting, urgent, all, completed
    var id: Self { self }

    var title: String {
        switch self {
        case .needsYou: L("Needs You")
        case .automatic: L("Automatic")
        case .waiting: L("Waiting on you")
        case .urgent: L("High priority")
        case .all: L("All messages")
        case .completed: L("Completed")
        }
    }

    var symbol: String {
        switch self {
        case .needsYou: "tray.fill"
        case .automatic: "timer"
        case .waiting: "hand.raised.fill"
        case .urgent: "exclamationmark.circle.fill"
        case .all: "tray.full.fill"
        case .completed: "checkmark"
        }
    }

    var isAttention: Bool { self != .all && self != .completed }

    var band: AttentionBand? {
        switch self {
        case .automatic: .autoDecision
        case .waiting: .blocked
        case .urgent: .declaredPriority
        default: nil
        }
    }
}

enum OverviewDestination: Hashable {
    case category(OverviewCategory)
    case session(String)
    case panels
}

struct OverviewSnapshot {
    let history: [HistoryMessage]
    let attention: [AttentionItem]
    let sessions: [SessionGroup]
    let now: Date

    init(history: [HistoryMessage], live: OptionMessage?, now: Date) {
        self.history = AttentionRanking.merge(history: history, live: live)
        self.attention = AttentionRanking.items(history: history, live: live, now: now)
        self.sessions = SessionGrouping.groupBySession(self.history)
        self.now = now
    }

    func count(_ category: OverviewCategory) -> Int {
        messages(for: .category(category)).count
    }

    func messages(for destination: OverviewDestination) -> [HistoryMessage] {
        switch destination {
        case let .session(id):
            return history.filter { SessionGrouping.sessionKey(for: $0) == id }
        case let .category(category) where category.isAttention:
            return attention.filter {
                if category == .urgent { return $0.priorityRank < 2 }
                return category.band == nil || $0.band(at: now) == category.band
            }.map(\.message)
        case .category(.completed):
            return history.filter(Self.isCompleted)
        default:
            return history
        }
    }

    func title(for destination: OverviewDestination) -> String {
        switch destination {
        case let .category(category): category.title
        case let .session(id): sessions.first { $0.id == id }?.label ?? L("Session")
        case .panels: L("Panels")
        }
    }

    private static func isCompleted(_ message: HistoryMessage) -> Bool {
        let direction = message.direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let status = message.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return direction == "agent_to_boss"
            && (["replied", "resolved", "expired"].contains(status) || message.metadata?.isExpired == true)
    }
}
