// Exclusive session buckets built from the same decision and activity rules as Today.
// Exports: SessionDirectory with needsYou, working, and idle session arrays.
// Dependencies: TodaySnapshot, TodaySession, HistoryMessage, and Foundation.

import Foundation

public struct SessionDirectory: Equatable, Sendable {
    public let needsYou: [TodaySession]
    public let working: [TodaySession]
    public let idle: [TodaySession]

    public init(
        history: [HistoryMessage], requiredInputs: [HistoryMessage] = [],
        withdrawn: Set<MessageID> = [], now: Date
    ) {
        let messages = TodayMessageRules.merge(history: history, requiredInputs: requiredInputs)
        let decisions = AttentionModel.items(from: messages.filter { !withdrawn.contains($0.id) }, now: now)
        self.init(sessions: TodaySession.summaries(messages: messages, decisions: decisions), now: now)
    }

    init(sessions: [TodaySession], now: Date) {
        needsYou = sessions.filter(\.needsYou)
        working = sessions.filter { !$0.needsYou && $0.hasLiveWork(now: now) }
        idle = sessions.filter { !$0.needsYou && !$0.hasLiveWork(now: now) }
    }
}
