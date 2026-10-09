// Shared session summaries and live-work classification for Today and Sessions.
// Exports: TodaySession with provenance, latest status text, activity, and needsYou.
// Dependencies: Foundation, HistoryMessage, SessionGrouping, and TodayMessageRules.

import Foundation

public struct TodaySession: Identifiable, Equatable, Sendable {
    public let id: String
    public let projectLabel: String
    public let branch: String?
    public let agentName: String?
    public let status: String?
    /// Latest message body, suitable for the current step or last-message row.
    public let statusText: String
    /// Nil when the session contains no parseable activity timestamp.
    public let lastActivityDate: Date?
    public let needsYou: Bool

    /// Inclusive fifteen-minute window; explicit `working` status remains live at any age.
    public static let activityWindow: TimeInterval = 15 * 60

    /// Future or malformed timestamps cannot establish recent activity.
    public func hasLiveWork(now: Date) -> Bool {
        TodayMessageRules.statusWord(status) == "working"
            || TodayMessageRules.isRecent(lastActivityDate, window: Self.activityWindow, now: now)
    }

    static func summaries(messages: [HistoryMessage], decisions: [AttentionItem]) -> [TodaySession] {
        let needsYou = Set(decisions.map { SessionGrouping.sessionKey(for: $0.message) })
        let buckets = Dictionary(grouping: messages, by: SessionGrouping.sessionKey(for:))
        return buckets.map { id, messages in
            make(id: id, messages: messages, needsYou: needsYou.contains(id))
        }.sorted {
            let left = $0.lastActivityDate ?? .distantPast
            let right = $1.lastActivityDate ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
    }

    private static func make(id: String, messages: [HistoryMessage], needsYou: Bool) -> TodaySession {
        let newest = messages.sorted(by: TodayMessageRules.newestFirst)
        let branch = newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.sessionBranch) }.first
        let label = newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.sessionLabel) }.first
        return TodaySession(
            id: id,
            projectLabel: label ?? branch ?? fallbackLabel(id),
            branch: branch,
            agentName: newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.agentName) }.first,
            status: newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.sessionStatus) }.first,
            statusText: newest.first?.body ?? "",
            lastActivityDate: newest.compactMap(TodayMessageRules.createdDate).max(),
            needsYou: needsYou
        )
    }

    private static func fallbackLabel(_ id: String) -> String {
        if id == SessionGrouping.directSessionID { return "Direct" }
        return String(id.replacingOccurrences(of: "-", with: "").prefix(8))
    }
}
