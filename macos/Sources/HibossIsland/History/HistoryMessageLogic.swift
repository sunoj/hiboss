// Testable logic for filtering, searching, and presenting history messages.
// Exports: HistorySegment, HistoryTimestamp, and HistoryMessage display helpers.
// Dependencies: Foundation date parsing and HibossKit HistoryMessage.

import Foundation
import HibossKit

enum HistorySegment: String, CaseIterable, Identifiable {
    case all
    case unread
    case blocking

    var id: Self { self }

    func title(unreadCount: Int) -> String {
        switch self {
        case .all: "All"
        case .unread: "Unread \(unreadCount)"
        case .blocking: "Blocking"
        }
    }

    func includes(_ message: HistoryMessage) -> Bool {
        switch self {
        case .all: true
        case .unread: message.isUnreadHistoryMessage
        case .blocking: message.isBlockingHistoryMessage
        }
    }
}

struct SessionGroup: Identifiable, Equatable {
    let id: String
    let label: String
    let agentName: String?
    let status: String?
    let messages: [HistoryMessage]

    var isExpandedByDefault: Bool {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "working", "waiting", "blocked": true
        default: false
        }
    }
}

enum HistoryMessageLogic {
    static let directSessionID = "direct"

    static func filtered(
        _ messages: [HistoryMessage],
        segment: HistorySegment,
        searchText: String
    ) -> [HistoryMessage] {
        messages.filter { message in
            segment.includes(message) && message.matchesHistorySearch(searchText)
        }
    }

    static func unreadCount(in messages: [HistoryMessage]) -> Int {
        messages.filter(\.isUnreadHistoryMessage).count
    }

    /// Groups already-filtered messages by `sessionId`. Nil IDs share a trailing "Direct" bucket.
    /// Groups are ordered by newest `createdAt` descending; order within a group is preserved.
    static func groupBySession(_ messages: [HistoryMessage]) -> [SessionGroup] {
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

    private static func sessionKey(for message: HistoryMessage) -> String {
        let trimmed = message.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? directSessionID : trimmed
    }

    private static func makeGroup(id: String, messages: [HistoryMessage]) -> SessionGroup {
        SessionGroup(
            id: id,
            label: groupLabel(id: id, messages: messages),
            agentName: messages.lazy.compactMap { clean($0.agentName) }.first,
            status: messages.reversed().lazy.compactMap { clean($0.sessionStatus) }.first,
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
        messages.compactMap { HistoryTimestamp.date(from: $0.createdAt) }.max() ?? .distantPast
    }
}

enum HistoryTimestamp {
    static func date(from rawValue: String) -> Date? {
        (try? Date(rawValue, strategy: .iso8601))
            ?? (try? Date(
                rawValue,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ))
            ?? dateFormatter("yyyy-MM-dd HH:mm:ss").date(from: rawValue)
    }

    static func shortLocalTime(
        from rawValue: String,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date = date(from: rawValue) else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}

extension HistoryMessage {
    var isBossHistoryMessage: Bool {
        normalizedDirection == "boss_to_agent"
    }

    var isUnreadHistoryMessage: Bool {
        normalizedStatus == "delivered" || normalizedStatus == "unread"
    }

    var isBlockingHistoryMessage: Bool {
        hasActiveHistoryOptions && !isResolvedHistoryMessage
    }

    var historyDisplayName: String {
        isBossHistoryMessage ? "Me" : clean(agentName) ?? "Agent"
    }

    var historyMonogram: String {
        HistoryMessage.monogram(
            agentName: agentName,
            isBossMessage: isBossHistoryMessage
        )
    }

    var historyTimestamp: String {
        HistoryTimestamp.shortLocalTime(from: createdAt)
    }

    var historyDirectionGlyph: String {
        switch normalizedDirection {
        case "agent_to_boss": "arrow.right"
        case "boss_to_agent": "arrow.left"
        default: "arrow.left.arrow.right"
        }
    }

    var historyDirectionAccessibilityLabel: String {
        switch normalizedDirection {
        case "agent_to_boss": "To boss"
        case "boss_to_agent": "From boss"
        default: "Peer message"
        }
    }

    /// `nil` for normal priority. A glyph on every row is noise — an empty circle beside each
    /// name says nothing, and drowns the two priorities that actually want attention. Mail
    /// shows a flag only when there is a flag.
    var historyPriorityGlyph: String? {
        switch priority.lowercased() {
        case "critical": "exclamationmark.octagon.fill"
        case "high": "exclamationmark.triangle.fill"
        case "low": "arrow.down.circle"
        default: nil
        }
    }

    var historyPriorityAccessibilityLabel: String {
        let cleaned = clean(priority)?.capitalized ?? "Normal"
        return "\(cleaned) priority"
    }

    /// Kept for tests and any text surfaces; History rows use SF Symbols instead.
    var historyPriorityModeLabel: String {
        [priority, mode]
            .compactMap(clean)
            .map { $0.uppercased() }
            .joined(separator: " · ")
    }

    /// Kept for tests and any text surfaces; History rows no longer show status chips.
    var historyStatusChip: String {
        switch normalizedStatus {
        case "replied": "✓ replied"
        case "read": "● read"
        case "expired": "● expired"
        default: "● \(normalizedStatus)"
        }
    }

    static func monogram(agentName: String?, isBossMessage: Bool) -> String {
        if isBossMessage { return "Me" }
        let cleaned = clean(agentName) ?? "Agent"
        let parts = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let letters = monogramLetters(from: parts.isEmpty ? [cleaned] : parts)
        return letters.uppercased()
    }

    func matchesHistorySearch(_ searchText: String) -> Bool {
        let terms = searchText
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !terms.isEmpty else { return true }
        let haystack = searchableHistoryText.lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }

    private var hasActiveHistoryOptions: Bool {
        guard metadata?.isExpired != true else { return false }
        return options.contains { clean($0) != nil }
    }

    private var isResolvedHistoryMessage: Bool {
        ["replied", "expired", "resolved"].contains(normalizedStatus)
    }

    private var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedDirection: String {
        direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var searchableHistoryText: String {
        [
            body,
            agentName,
            direction,
            status,
            priority,
            channel,
            mode,
            options.joined(separator: " "),
        ].compactMap { $0 }.joined(separator: " ")
    }

    private static func monogramLetters(from parts: [String]) -> String {
        if parts.count >= 2 {
            return parts.prefix(2).compactMap(\.first).map(String.init).joined()
        }
        return String(parts[0].prefix(2))
    }
}

private func clean(_ value: String?) -> String? {
    let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
}
