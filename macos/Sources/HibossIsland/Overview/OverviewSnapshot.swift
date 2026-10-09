// Defines overview destinations and derives tile counts from the exact destination messages.
// Exports: OverviewCategory, OverviewDestination, OverviewSnapshot.
// Dependencies: HibossKit history/session models and TodayProjection.

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

    var group: AttentionGroup? {
        switch self {
        case .automatic: .autoDecision
        case .waiting: .waitingOnYou
        case .urgent: .priority
        default: nil
        }
    }
}

enum OverviewDestination: Hashable {
    case category(OverviewCategory)
    case session(String)
    case today
    case deviceRequests
    case box
    case progress
}

struct OverviewSnapshot {
    let history: [HistoryMessage]
    let attention: [AttentionItem]
    let sessions: [SessionGroup]
    let now: Date
    let today: TodaySnapshot
    let answerability: AnswerableDecisions

    init(history: [HistoryMessage], live: OptionMessage?, now: Date,
         health: TodayHealth = .loading, coverageComplete: Bool = false,
         requiredInputs: [HistoryMessage] = [], requiredInputLoaded: Bool = false) {
        self.history = TodayProjection.merge(history: history, live: live, requiredInputs: requiredInputs)
        self.today = TodaySnapshot(history: self.history, requiredInputs: requiredInputs,
            health: health,
            coverageComplete: coverageComplete, now: now)
        self.attention = today.decisions
        self.answerability = AnswerableDecisions(isLoaded: requiredInputLoaded,
            openIDs: Set(today.decisions.map(\.id)))
        self.sessions = SessionGrouping.groupBySession(self.history)
        self.now = now
    }

    func count(_ category: OverviewCategory) -> Int {
        messages(for: .category(category)).count
    }

    func messages(for destination: OverviewDestination) -> [HistoryMessage] {
        switch destination {
        case .today:
            return attention.map(\.message)
        case .deviceRequests, .box, .progress:
            return []
        case let .session(id):
            return history.filter { SessionGrouping.sessionKey(for: $0) == id }
        case let .category(category) where category.isAttention:
            return attention.filter {
                if category == .urgent { return $0.priorityRank < 2 }
                if category == .waiting {
                    return $0.group == .waitingOnYou || ($0.group == .priority && $0.priorityRank == 2)
                }
                return category.group == nil || $0.group == category.group
            }.map(\.message)
        case .category(.completed):
            return history.filter { Self.isCompleted($0, at: now) }
        default:
            return history
        }
    }

    func title(for destination: OverviewDestination) -> String {
        switch destination {
        case let .category(category): category.title
        case let .session(id): sessions.first { $0.id == id }?.label ?? L("Session")
        case .today: L("Today")
        case .deviceRequests: L("Device Requests")
        case .box: L("Box")
        case .progress: L("Progress")
        }
    }

    private static func isCompleted(_ message: HistoryMessage, at now: Date) -> Bool {
        let direction = message.direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let status = message.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let deadlineElapsed = message.isDecision && (message.expirationDate.map { $0 <= now } ?? false)
        return direction == "agent_to_boss"
            && (["replied", "resolved", "expired"].contains(status)
                || message.metadata?.isExpired == true || deadlineElapsed)
    }
}
