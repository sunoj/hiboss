// Parses ISO history timestamps and formats them with the system locale.
// Exports: HistoryMessage.createdDate and relativeCreatedAt display helpers.
// Dependencies: Foundation date parsing over the shared HistoryMessage model.

import Foundation
import HibossKit

extension HistoryMessage {
    /// The parsed `created_at`, tolerant of fractional seconds and plain formats.
    var createdDate: Date? { ISOTimestamp.date(from: createdAt) }

    /// Locale-aware relative time — empty when unparseable.
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

extension ProgressPost {
    var createdDate: Date? { ISOTimestamp.date(from: createdAt) }

    var relativeCreatedAt: String {
        guard let date = createdDate else { return "" }
        return RelativeTime.short(from: date)
    }
}

enum RelativeTime {
    /// System relative formatting, falling back to a short date for older items.
    static func short(
        from date: Date,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 604_800 {
            return relativeFormatter(locale: locale).localizedString(for: date, relativeTo: now)
        }
        let calendar = Calendar(identifier: .gregorian)
        var localized = calendar
        localized.locale = locale
        if localized.component(.year, from: date) == localized.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        }
        return date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }

    private static func relativeFormatter(locale: Locale) -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = locale
        return formatter
    }
}
