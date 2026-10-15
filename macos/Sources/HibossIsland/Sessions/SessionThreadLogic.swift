// Pure session presentation: pinned decisions, activity ordering, and consecutive updates.
// Exports: SessionThreadLogic, SessionConversationCard, and SessionReactionChip.
// Dependencies: Foundation and HibossKit thread/reaction models; no view state.

import Foundation
import HibossKit

struct SessionConversationCard: Identifiable {
    let threads: [MessageThread]
    var id: MessageID { threads[0].id }
    var lastActivity: Date { threads.map(SessionThreadLogic.lastActivity).max() ?? .distantPast }
}

struct SessionConversationDay: Identifiable {
    let id: Date
    let cards: [SessionConversationCard]
}

struct SessionReactionChip: Equatable {
    let emoji: String
    let count: Int
    var text: String { count > 1 ? "\(emoji) \(count)" : emoji }
    var accessibilityLabel: String { "\(emoji), \(count)" }
}

struct SessionThreadLogic {
    let needsYou: [MessageThread]
    let conversation: [SessionConversationCard]

    init(threads: [MessageThread], answerability: AnswerableDecisions, now: Date) {
        needsYou = threads.filter {
            answerability.state(for: $0.id) == .open && $0.replies.isEmpty
                && $0.message.canAnswerHistory(at: now)
        }.sorted {
            let left = $0.message.expirationDate ?? .distantFuture
            let right = $1.message.expirationDate ?? .distantFuture
            return left == right ? Self.older($0, $1) : left < right
        }
        let pinned = Set(needsYou.map(\.id))
        // Group in creation order before sorting cards by activity. A different sender or
        // a decision breaks a run even when that decision is pinned in Needs you.
        var cards: [SessionConversationCard] = []
        for thread in threads.sorted(by: Self.older) {
            if let previous = cards.last, let tail = previous.threads.last,
               Self.canMerge(tail, thread) {
                cards[cards.count - 1] = SessionConversationCard(threads: previous.threads + [thread])
            } else {
                cards.append(SessionConversationCard(threads: [thread]))
            }
        }
        conversation = cards.filter { !pinned.contains($0.id) }.sorted {
            $0.lastActivity == $1.lastActivity
                ? $0.id.rawValue < $1.id.rawValue : $0.lastActivity > $1.lastActivity
        }
    }

    func days(calendar: Calendar = .autoupdatingCurrent) -> [SessionConversationDay] {
        var days: [SessionConversationDay] = []
        for card in conversation {
            let date = calendar.startOfDay(for: card.lastActivity)
            if let previous = days.last, previous.id == date {
                days[days.count - 1] = SessionConversationDay(id: date, cards: previous.cards + [card])
            } else {
                days.append(SessionConversationDay(id: date, cards: [card]))
            }
        }
        return days
    }

    static func lastActivity(_ thread: MessageThread) -> Date {
        ([thread.message] + thread.entries).flatMap { message in
            [ISODate.parse(message.createdAt)] + (message.metadata?.reactions ?? []).map {
                ISODate.parse($0.createdAt)
            }
        }.compactMap { $0 }.max() ?? .distantPast
    }

    static func reactionChips(_ message: HistoryMessage) -> [SessionReactionChip] {
        (message.metadata?.reactionGroups ?? []).map { SessionReactionChip(emoji: $0.emoji, count: $0.count) }
    }

    static func hasDetails(_ message: HistoryMessage) -> Bool {
        // Body, content and attachments are already rendered inline.
        !(message.metadata?.files.isEmpty ?? true)
    }

    static func dayTitle(_ date: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return L("Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return L("Yesterday") }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style: Date.FormatStyle = sameYear
            ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
        style.calendar = calendar
        return date.formatted(style)
    }

    private static func older(_ left: MessageThread, _ right: MessageThread) -> Bool {
        let a = ISODate.parse(left.message.createdAt) ?? .distantPast
        let b = ISODate.parse(right.message.createdAt) ?? .distantPast
        return a == b ? left.id.rawValue < right.id.rawValue : a < b
    }

    private static func canMerge(_ left: MessageThread, _ right: MessageThread) -> Bool {
        let a = left.message, b = right.message
        guard a.direction == "agent_to_boss", b.direction == a.direction,
              let agent = a.agentName, !agent.isEmpty, b.agentName == agent,
              !a.isDecision, !b.isDecision, left.entries.isEmpty, right.entries.isEmpty,
              let start = ISODate.parse(a.createdAt), let end = ISODate.parse(b.createdAt) else {
            return false
        }
        return end.timeIntervalSince(start) <= 600
    }
}
