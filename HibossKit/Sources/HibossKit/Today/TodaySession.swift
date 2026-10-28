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
    /// The server's session heartbeat (`last_seen_at`), when the app has the inventory.
    public var lastSeenDate: Date? = nil

    /// Inclusive fifteen-minute window for messages and heartbeats.
    public static let activityWindow: TimeInterval = 15 * 60
    /// Without a heartbeat, a `working` status counts only this long after the last message,
    /// so a status left behind by a session that went quiet days ago is not "working now".
    public static let staleStatusWindow: TimeInterval = 2 * 60 * 60

    /// Future or malformed timestamps cannot establish recent activity.
    public func hasLiveWork(now: Date) -> Bool {
        let recentMessage = TodayMessageRules.isRecent(lastActivityDate, window: Self.activityWindow, now: now)
        guard TodayMessageRules.statusWord(status) == "working" else { return recentMessage }
        if let lastSeenDate {
            return recentMessage || TodayMessageRules.isRecent(lastSeenDate, window: Self.activityWindow, now: now)
        }
        return TodayMessageRules.isRecent(lastActivityDate, window: Self.staleStatusWindow, now: now)
    }

    /// The merge order is newest first, with stable message-ID ties, and survives grouping.
    static func summaries(newestFirst messages: [HistoryMessage], decisions: [AttentionItem],
                          lastSeen: [String: Date] = [:]) -> [TodaySession] {
        let needsYou = Set(decisions.map { SessionGrouping.sessionKey(for: $0.message) })
        let buckets = Dictionary(grouping: messages, by: SessionGrouping.sessionKey(for:))
        return buckets.map { id, messages in
            var session = make(id: id, messages: messages, needsYou: needsYou.contains(id))
            session.lastSeenDate = lastSeen[id]
            return session
        }.sorted {
            let left = $0.lastActivityDate ?? .distantPast
            let right = $1.lastActivityDate ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
    }

    private static func make(id: String, messages newest: [HistoryMessage], needsYou: Bool) -> TodaySession {
        let branch = newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.sessionBranch) }.first
        let label = newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.sessionLabel) }.first
        return TodaySession(
            id: id,
            projectLabel: label ?? branch ?? fallbackLabel(id),
            branch: branch,
            agentName: newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.agentName) }.first,
            status: newest.lazy.compactMap { TodayMessageRules.nonEmpty($0.sessionStatus) }.first,
            statusText: newest.first?.body ?? "",
            lastActivityDate: newest.lazy.compactMap(TodayMessageRules.createdDate).first,
            needsYou: needsYou
        )
    }

    private static func fallbackLabel(_ id: String) -> String {
        if id == SessionGrouping.directSessionID { return "Direct" }
        return String(id.replacingOccurrences(of: "-", with: "").prefix(8))
    }
}
