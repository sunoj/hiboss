// Compact timestamps that preserve the user's calendar, locale, and time zone.
// Exports: SharedTimestamp.string for messages and recorded session/Box dates.
// Dependencies: Foundation and the app's existing localized Yesterday string.

import Foundation

enum SharedTimestamp {
    static func string(
        _ date: Date, now: Date = .now, calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("jm")
        let clock = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return yesterdayLabel(locale: locale) + " " + clock
        }
        let sameYear = calendar.dateInterval(of: .year, for: now)?.contains(date) == true
        let template = sameYear ? "MMMd" : "yMMMd" // i18n-exempt: localized date component templates
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date) + " " + clock
    }

    private static func yesterdayLabel(locale: Locale) -> String {
        if locale == .autoupdatingCurrent { return L("Yesterday") }
        let language = locale.language.languageCode?.identifier ?? "en"
        let resource = language == "zh" ? "zh-Hans" : language
        let bundle = appResourceBundle.path(forResource: resource, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? appResourceBundle
        let key: String.LocalizationValue = "Yesterday" // i18n-exempt: existing catalog key for injected locale
        return String(localized: key, bundle: bundle, locale: locale)
    }
}
