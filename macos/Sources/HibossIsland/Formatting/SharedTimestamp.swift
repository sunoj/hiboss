// Compact timestamps that preserve the user's calendar, locale, and time zone.
// Exports: SharedTimestamp.string for messages and recorded session/Box dates.
// Dependencies: Foundation duration/date formatters and the app string catalog.

import Foundation

enum SharedTimestamp {
    static func string(
        _ date: Date, now: Date = .now, calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0, elapsed < 12 * 3600 {
            return relative(elapsed, calendar: calendar, locale: locale)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jm")
        let clock = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return localized("Yesterday", locale: locale) + " " + clock // i18n-exempt: injected locale
        }
        let sameYear = calendar.dateInterval(of: .year, for: now)?.contains(date) == true
        let template = sameYear ? "MMMd" : "yMMMd" // i18n-exempt: localized date component templates
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date) + " " + clock
    }

    private static func relative(_ elapsed: TimeInterval, calendar: Calendar, locale: Locale) -> String {
        if elapsed < 60 { return localized("Just now", locale: locale) } // i18n-exempt: injected locale
        var calendar = calendar
        calendar.locale = locale
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        let minutes = Int(elapsed / 60)
        let parts: [(NSCalendar.Unit, Int)] = [(.hour, minutes / 60), (.minute, minutes % 60)]
        var duration = parts.compactMap { unit, value -> String? in
            guard value > 0 else { return nil }
            formatter.allowedUnits = unit
            return formatter.string(from: TimeInterval(value * (unit == .hour ? 3600 : 60)))
        }.joined(separator: locale.language.languageCode?.identifier == "zh" ? "" : " ")
        if locale.language.languageCode?.identifier == "en" {
            // Foundation pluralizes the short hour unit in some English regions.
            duration = duration.replacingOccurrences(of: "hrs", with: "hr")
        }
        return localized("\(duration) ago", locale: locale)
    }

    private static func localized(_ key: String.LocalizationValue, locale: Locale) -> String {
        if locale == .autoupdatingCurrent { return L(key) }
        let language = locale.language.languageCode?.identifier ?? "en"
        let resource = language == "zh" ? "zh-Hans" : language
        let bundle = appResourceBundle.path(forResource: resource, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? appResourceBundle
        return String(localized: key, bundle: bundle, locale: locale)
    }
}
