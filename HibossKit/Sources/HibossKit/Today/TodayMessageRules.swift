// Internal message normalization and merging for deterministic Today projections.
// Exports: TodayMessageRules within HibossKit; no app-specific display dependencies.
// Dependencies: Foundation, HistoryMessage, and ISODate.

import Foundation

enum TodayMessageRules {
    static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func statusWord(_ value: String?) -> String? {
        nonEmpty(value)?.lowercased()
    }

    // These are the same terminal statuses used by the iOS attention model.
    static func isResolved(_ message: HistoryMessage) -> Bool {
        message.status == "replied" || message.status == "expired"
    }

    static func createdDate(_ message: HistoryMessage) -> Date? {
        ISODate.parse(message.createdAt) ?? plainDate(message.createdAt)
    }

    private static func plainDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }

    /// Required inputs override history by ID; the last duplicate in each source wins.
    static func merge(history: [HistoryMessage], requiredInputs: [HistoryMessage]) -> [HistoryMessage] {
        var byID: [MessageID: HistoryMessage] = [:]
        for message in history + requiredInputs {
            byID[message.id] = message
        }
        return byID.values.sorted(by: newestFirst)
    }

    static func newestFirst(_ lhs: HistoryMessage, _ rhs: HistoryMessage) -> Bool {
        let left = createdDate(lhs) ?? .distantPast
        let right = createdDate(rhs) ?? .distantPast
        return left == right ? lhs.id.rawValue < rhs.id.rawValue : left > right
    }

    static func isRecent(_ date: Date?, window: TimeInterval, now: Date) -> Bool {
        guard let date else { return false }
        return date <= now && date >= now.addingTimeInterval(-window)
    }
}
