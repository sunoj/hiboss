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
        case .all: L("All")
        case .unread: L("Unread \(unreadCount)")
        case .blocking: L("Blocking")
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

enum HistoryMessageLogic {
    static func sessionTitle(group: SessionGroup, session: ProjectSession?) -> String {
        group.id == SessionGrouping.directSessionID ? L("Direct") : (session?.displayLabel ?? group.label)
    }

    static let directSessionID = SessionGrouping.directSessionID

    static func filtered(
        _ messages: [HistoryMessage],
        segment: HistorySegment,
        searchText: String
    ) -> [MessageThread] {
        filteredThreads(MessageThread.fold(messages), segment: segment, searchText: searchText)
    }

    static func filteredThreads(
        _ threads: [MessageThread], segment: HistorySegment, searchText: String
    ) -> [MessageThread] {
        threads.filter { thread in
            segment.includes(thread.message)
                && ([thread.message] + thread.replies).contains { $0.matchesHistorySearch(searchText) }
        }
    }

    static func scopedThreads(snapshot: OverviewSnapshot, scope: OverviewDestination) -> [MessageThread] {
        let threads = MessageThread.fold(snapshot.history)
        let ids = Set(snapshot.messages(for: scope).map(\.id))
        return threads.filter { ids.contains($0.id) }
    }

    static func unreadCount(in messages: [HistoryMessage]) -> Int {
        MessageThread.fold(messages).filter { $0.message.isUnreadHistoryMessage }.count
    }

    /// Groups already-filtered messages by session. Delegates to HibossKit.SessionGrouping.
    static func groupBySession(_ messages: [HistoryMessage]) -> [SessionGroup] {
        SessionGrouping.groupBySession(MessageThread.fold(messages).map(\.message))
    }
}

enum HistoryTimestamp {
    private static let sqlFormatter = dateFormatter("yyyy-MM-dd HH:mm:ss") // i18n-exempt: SQL parser

    static func date(from rawValue: String) -> Date? {
        (try? Date(rawValue, strategy: .iso8601))
            ?? (try? Date(
                rawValue,
                strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            ))
            ?? sqlFormatter.date(from: rawValue)
    }

    static func shortLocalTime(
        from rawValue: String,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date = date(from: rawValue) else { return L("Unknown") }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
            locale: locale, timeZone: timeZone))
    }

    /// Full date and time for detail views; the raw value when it cannot be parsed.
    static func localDateTime(
        from rawValue: String,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date = date(from: rawValue) else { return rawValue }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened,
            locale: locale, timeZone: timeZone))
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format // i18n-exempt: parses server SQL timestamps, never displayed
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
        canAnswerHistory(at: .now)
    }

    func canAnswerHistory(at now: Date) -> Bool {
        normalizedDirection == "agent_to_boss" && hasActiveHistoryOptions
            && !isResolvedHistoryMessage && (expirationDate.map { $0 > now } ?? true)
    }

    /// Server auto-selected on timeout — history only, never as if the boss chose.
    var isAutoDecidedHistoryMessage: Bool {
        metadata?.isExpired == true || normalizedStatus == "expired"
    }

    var historyAutoDecidedLabel: String? {
        guard isAutoDecidedHistoryMessage else { return nil }
        if let option = clean(defaultOption) {
            return L("Auto-decided · \(option)")
        }
        return L("Auto-decided")
    }

    var historyDisplayName: String {
        isBossHistoryMessage ? L("Me") : clean(agentName) ?? L("Agent")
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
        case "agent_to_boss": L("To boss")
        case "boss_to_agent": L("From boss")
        default: L("Peer message")
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
        let cleaned = clean(priority).map(localizedPriorityName) ?? L("Normal")
        return L("\(cleaned) priority")
    }

    var historyPriorityName: String {
        clean(priority).map(localizedPriorityName) ?? priority
    }

    /// Known server statuses read in the boss's language; unknown ones stay as sent.
    var historyStatusName: String {
        switch normalizedStatus {
        case "delivered": L("Delivered")
        case "unread": L("Unread")
        case "read": L("Read")
        case "replied": L("Replied")
        case "expired": L("Expired")
        case "resolved": L("Resolved")
        default: status
        }
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
        case "replied": L("✓ replied")
        case "read": L("● read")
        case "expired": L("● expired")
        default: L("● \(normalizedStatus)")
        }
    }

    static func monogram(agentName: String?, isBossMessage: Bool) -> String {
        if isBossMessage { return L("Me") }
        let cleaned = clean(agentName) ?? L("Agent")
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
            content,
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

private func localizedPriorityName(_ raw: String) -> String {
    switch raw.lowercased() {
    case "critical": L("Critical")
    case "high": L("High")
    case "normal": L("Normal")
    case "low": L("Low")
    default: raw.capitalized
    }
}

private func clean(_ value: String?) -> String? {
    let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
}
