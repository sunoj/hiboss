// Pure Today projection combining decisions, live sessions, results, and connection health.
// Exports: TodaySnapshot; all-clear requires a live connection and complete coverage.
// Dependencies: Foundation, AttentionModel, TodaySession, SessionDirectory, and TodayHealth.

import Foundation

public struct TodaySnapshot: Equatable, Sendable {
    public let decisions: [AttentionItem]
    public let working: [TodaySession]
    public let delivered: [HistoryMessage]
    public let health: TodayHealth
    public let coverageComplete: Bool
    public let sessionDirectory: SessionDirectory

    /// Delivered results cover the inclusive last 24 hours and retain at most 20 messages.
    public static let deliveredWindow: TimeInterval = 24 * 60 * 60
    public static let deliveredLimit = 20

    public var isAllClear: Bool {
        guard decisions.isEmpty, coverageComplete else { return false }
        if case .live = health { return true }
        return false
    }

    /// No clock reads: callers supply both freshness evidence and the evaluation time.
    /// Required-input duplicates replace history; withdrawn IDs cannot appear in decisions or results.
    /// Only the server's required inputs can be decisions: history adds context, never an open
    /// decision, so an answered or retired message cannot reappear as answerable.
    public init(
        history: [HistoryMessage], requiredInputs: [HistoryMessage] = [],
        withdrawn: Set<MessageID> = [], health: TodayHealth, coverageComplete: Bool, now: Date,
        lastSeen: [String: Date] = [:]
    ) {
        let messages = TodayMessageRules.merge(history: history, requiredInputs: requiredInputs)
        let visible = messages.filter { !withdrawn.contains($0.id) }
        let decisions = TodayMessageRules.openDecisions(requiredInputs, withdrawn: withdrawn, now: now)
        let sessions = TodaySession.summaries(messages: messages, decisions: decisions, lastSeen: lastSeen)
        self.decisions = decisions
        working = sessions.filter { $0.hasLiveWork(now: now) }
        delivered = Self.results(from: visible, decisions: decisions, now: now)
        self.health = health
        self.coverageComplete = coverageComplete
        sessionDirectory = SessionDirectory(sessions: sessions, now: now)
    }

    private static func results(
        from messages: [HistoryMessage], decisions: [AttentionItem], now: Date
    ) -> [HistoryMessage] {
        let openIDs = Set(decisions.map(\.id))
        return Array(messages.filter {
            $0.direction == "agent_to_boss" && $0.mode != "blocking"
                && !openIDs.contains($0.id)
                && (TodayMessageRules.isResolved($0) || $0.options.isEmpty)
                && TodayMessageRules.isRecent(
                    TodayMessageRules.createdDate($0), window: deliveredWindow, now: now
                )
        }.prefix(deliveredLimit))
    }
}
