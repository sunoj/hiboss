// Session conversation ordering and consecutive standalone update grouping.
// Exports SessionThreads and Card; depends on HibossKit's shared thread fold.

import Foundation
import HibossKit

struct SessionThreads {
    struct Card: Identifiable, Equatable {
        var threads: [MessageThread]
        var id: MessageID { threads[0].id }
        var lastActivity: Date { threads.map(SessionThreads.lastActivity).max() ?? .distantPast }
    }

    let needsYou: [MessageThread]
    let conversation: [Card]

    init(messages: [HistoryMessage], isOpen: (MessageID) -> Bool) {
        let threads = MessageThread.fold(messages).sorted {
            let left = $0.message.createdDate ?? .distantPast
            let right = $1.message.createdDate ?? .distantPast
            return left == right ? $0.id.rawValue < $1.id.rawValue : left < right
        }
        needsYou = threads.filter {
            $0.message.isDecision && $0.replies.isEmpty
                && ($0.outcome == .open || $0.message.options.isEmpty) && isOpen($0.id)
        }.sorted {
            let left = $0.message.expirationDate ?? .distantFuture
            let right = $1.message.expirationDate ?? .distantFuture
            if left != right { return left < right }
            let first = $0.message.createdDate ?? .distantPast
            let second = $1.message.createdDate ?? .distantPast
            return first == second ? $0.id.rawValue < $1.id.rawValue : first < second
        }
        let pinned = Set(needsYou.map(\.id))
        var cards: [Card] = []
        // Pinned decisions still break consecutive runs of standalone updates.
        for thread in threads {
            if !pinned.contains(thread.id), let previous = cards.last?.threads.last,
               Self.canMerge(previous, thread), let index = cards.indices.last {
                cards[index].threads.append(thread)
            } else {
                cards.append(Card(threads: [thread]))
            }
        }
        conversation = cards.filter { !pinned.contains($0.id) }.sorted {
            $0.lastActivity == $1.lastActivity
                ? $0.id.rawValue < $1.id.rawValue : $0.lastActivity > $1.lastActivity
        }
    }

    static func lastActivity(_ thread: MessageThread) -> Date {
        ([thread.message] + thread.entries).flatMap { message in
            [message.createdDate ?? .distantPast]
                + (message.metadata?.reactions.compactMap { $0.createdAt.flatMap(ISODate.parse) } ?? [])
        }.max() ?? .distantPast
    }

    static func hasDetails(_ message: HistoryMessage) -> Bool {
        let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (!content.isEmpty && content != message.body.trimmingCharacters(in: .whitespacesAndNewlines))
            || !(message.metadata?.files.isEmpty ?? true)
    }

    private static func canMerge(_ first: MessageThread, _ next: MessageThread) -> Bool {
        guard !first.isBoss, !next.isBoss, first.entries.isEmpty, next.entries.isEmpty,
              first.message.options.isEmpty, next.message.options.isEmpty,
              !first.message.isDecision, !next.message.isDecision,
              let agent = first.message.agentName, agent == next.message.agentName,
              let start = first.message.createdDate, let end = next.message.createdDate else { return false }
        return end.timeIntervalSince(start) <= 600
    }
}
