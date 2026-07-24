// Groups history messages by agent session for inbox and history surfaces.
// Exports: SessionGroup and SessionGrouping.groupBySession.
// Dependencies: HistoryMessage and Foundation date parsing.

import Foundation

public struct SessionGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let agentName: String?
    public let status: String?
    public let branch: String?
    public let messages: [HistoryMessage]

    public var isExpandedByDefault: Bool {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "working", "waiting", "blocked": true
        default: false
        }
    }
}

public enum SessionGrouping {
    public static let directSessionID = "direct"

    /// Groups messages by `sessionId`. Nil IDs share a trailing "Direct" bucket.
    /// Groups are ordered by newest `createdAt` descending; order within a group is preserved.
    public static func groupBySession(_ messages: [HistoryMessage]) -> [SessionGroup] {
        var order: [String] = []
        var buckets: [String: [HistoryMessage]] = [:]
        for message in messages {
            let key = sessionKey(for: message)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key, default: []].append(message)
        }
        return order.compactMap { key in
            guard let groupMessages = buckets[key], !groupMessages.isEmpty else { return nil }
            return makeGroup(id: key, messages: groupMessages)
        }
        .sorted { newestDate(in: $0.messages) > newestDate(in: $1.messages) }
    }

    /// The grouping key for a message — its trimmed `sessionId`, or the shared
    /// "direct" bucket for nil/blank ids. Public so a session detail view can
    /// select exactly the messages a `SessionGroup` was built from.
    public static func sessionKey(for message: HistoryMessage) -> String {
        let trimmed = message.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? directSessionID : trimmed
    }

    private static func makeGroup(id: String, messages: [HistoryMessage]) -> SessionGroup {
        SessionGroup(
            id: id,
            label: groupLabel(id: id, messages: messages),
            agentName: messages.lazy.compactMap { clean($0.agentName) }.first,
            status: messages.reversed().lazy.compactMap { clean($0.sessionStatus) }.first,
            branch: messages.lazy.compactMap { clean($0.sessionBranch) }.first,
            messages: messages
        )
    }

    private static func groupLabel(id: String, messages: [HistoryMessage]) -> String {
        if id == directSessionID { return "Direct" }
        return messages.lazy.compactMap { clean($0.sessionLabel) }.first
            ?? messages.lazy.compactMap { clean($0.sessionBranch) }.first
            ?? shortSessionID(id)
    }

    private static func shortSessionID(_ id: String) -> String {
        let compact = id.replacingOccurrences(of: "-", with: "")
        return String(compact.prefix(8))
    }

    private static func newestDate(in messages: [HistoryMessage]) -> Date {
        messages.compactMap { HistoryCreatedAt.date(from: $0.createdAt) }.max() ?? .distantPast
    }
}

enum HistoryCreatedAt {
    static func date(from rawValue: String) -> Date? {
        (try? Date(rawValue, strategy: .iso8601))
            ?? (try? Date(
                rawValue,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ))
            ?? dateFormatter("yyyy-MM-dd HH:mm:ss").date(from: rawValue)
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}

private func clean(_ value: String?) -> String? {
    let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
}
