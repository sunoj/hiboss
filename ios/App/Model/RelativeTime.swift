// Parses ISO history timestamps and formats them as short relative strings.
// Exports: HistoryMessage.createdDate and relativeCreatedAt display helpers.
// Dependencies: Foundation date parsing over the shared HistoryMessage model.

import Foundation
import HibossKit

extension HistoryMessage {
    /// The parsed `created_at`, tolerant of fractional seconds and plain formats.
    var createdDate: Date? { ISOTimestamp.date(from: createdAt) }

    /// e.g. "just now", "4m ago", "2h ago" — empty when unparseable.
    var relativeCreatedAt: String {
        guard let date = createdDate else { return "" }
        return RelativeTime.short(from: date)
    }
}

enum ISOTimestamp {
    static func date(from raw: String) -> Date? {
        (try? Date(raw, strategy: .iso8601))
            ?? (try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? plain.date(from: raw)
    }

    private static let plain: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

enum RelativeTime {
    /// Compact "Nm ago" style, falling back to a short date for older items.
    static func short(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 45 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d ago" }
        let calendar = Calendar.current
        // Include the year once it isn't the current one, so "Jul 24" can't be
        // mistaken for a different year's date.
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}
