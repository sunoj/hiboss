// Parses ISO timestamps and formats recorded times using the user's locale and calendar.
// Exports model date helpers, RelativeTime and the minute-updating RecordedTimeText.
// Dependencies: Foundation, SwiftUI and shared history/progress models.

import Foundation
import HibossKit
import SwiftUI

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
        ISODate.parse(raw) ?? plain.date(from: raw)
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
    /// Relative below twelve hours; absolute for older records and future clock skew.
    static func short(
        from date: Date,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 0, seconds < 43_200 else {
            return absolute(from: date, now: now, locale: locale, calendar: calendar)
        }
        let bundle = localizedBundle(locale)
        let compactWords = ["en", "zh"].contains(locale.language.languageCode?.identifier ?? "")
        if seconds < 60 {
            return compactWords ? String(localized: "Just now", bundle: bundle, locale: locale)
                : namedPeriod(DateComponents(second: 0), locale: locale)
        }
        if compactWords {
            let minutes = Int(seconds / 60)
            if minutes < 60 {
                return String(localized: "Recorded minutes \(minutes)", bundle: bundle, locale: locale)
            }
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 {
                return String(localized: "Recorded hours \(hours)", bundle: bundle, locale: locale)
            }
            return String(localized: "Recorded hours \(hours) minutes \(remainder)",
                          bundle: bundle, locale: locale)
        }
        let abbreviated = relativeFormatter(locale: locale, style: .abbreviated)
            .localizedString(for: date, relativeTo: now)
        // CLDR's narrowest past form can be signed; the short style reads as "ago" there.
        guard abbreviated.hasPrefix("-") || abbreviated.hasPrefix("\u{2212}") else { return abbreviated }
        return relativeFormatter(locale: locale, style: .short).localizedString(for: date, relativeTo: now)
    }

    /// Deadline callers also use this path, with the current calendar year omitted.
    static func absolute(
        from date: Date, now: Date = .now, locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent, includesTime: Bool = true
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        if !includesTime {
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "yMMMd")
            return formatter.string(from: date)
        }
        formatter.setLocalizedDateFormatFromTemplate("jm")
        let time = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            if ["en", "zh"].contains(locale.language.languageCode?.identifier ?? "") {
                return String(localized: "Yesterday \(time)", bundle: localizedBundle(locale), locale: locale)
            }
            return namedPeriod(DateComponents(day: -1), locale: locale) + " " + time
        }
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMdjm" : "yMMMdjm")
        return formatter.string(from: date)
    }

    private static func namedPeriod(_ components: DateComponents, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: components)
    }

    private static func localizedBundle(_ locale: Locale) -> Bundle {
        let app = Bundle(identifier: "ai.hiboss.app") ?? .main
        let language = Bundle.preferredLocalizations(
            from: app.localizations, forPreferences: [locale.identifier]).first
        return language.flatMap { app.path(forResource: $0, ofType: "lproj") }
            .flatMap(Bundle.init(path:)) ?? app
    }

    private static func relativeFormatter(
        locale: Locale, style: RelativeDateTimeFormatter.UnitsStyle
    ) -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = style
        formatter.locale = locale
        return formatter
    }
}

struct RecordedTimeText: View {
    let date: Date
    var label: (String) -> Text = { Text(verbatim: $0) }
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar

    var body: some View {
        TimelineView(.everyMinute) { _ in
            label(RelativeTime.short(from: date, now: .now, locale: locale, calendar: calendar))
        }
    }
}
