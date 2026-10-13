// Unified Box titles, metadata, calendar sections and localized timestamps.
// Exports: BoxTime, BoxDateSection and BoxItem display properties.
// Dependencies: Foundation, HibossKit and the app string catalog.

import Foundation
import HibossKit
import UniformTypeIdentifiers

enum BoxDateSection: Int, CaseIterable, Identifiable {
    case today, yesterday, thisWeek, earlier
    var id: Self { self }
    var title: String {
        switch self {
        case .today: L("Today")
        case .yesterday: L("Yesterday")
        case .thisWeek: L("This week")
        case .earlier: L("Earlier")
        }
    }

    static func section(for timestamp: String, now: Date, calendar: Calendar = .current) -> Self {
        guard let date = ISODate.parse(timestamp) else { return .earlier }
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true { return .thisWeek }
        return .earlier
    }
}

enum BoxTime {
    static func absolute(
        _ timestamp: String, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String {
        guard let date = ISODate.parse(timestamp) else { return timestamp }
        return formatted(date, template: "yyyyMMMd", locale: locale, timeZone: timeZone)
            + " " + formatted(date, template: "HHmm", locale: locale, timeZone: timeZone)
    }

    static func relative(
        _ timestamp: String, now: Date = .now, locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        guard let date = ISODate.parse(timestamp) else { return timestamp }
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 60 { return localized("\(elapsed) seconds ago", locale: locale) }
        if elapsed < 3600 { return localized("\(elapsed / 60) minutes ago", locale: locale) }
        let clock = formatted(date, template: "HHmm", locale: locale, timeZone: calendar.timeZone)
        if BoxDateSection.section(for: timestamp, now: now, calendar: calendar) == .yesterday {
            return localized("Yesterday", locale: locale) + " " + clock
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func formatted(
        _ date: Date, template: String, locale: Locale, timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func localized(_ key: String.LocalizationValue, locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        let resource = language == "zh" ? "zh-Hans" : language
        let bundle = appResourceBundle.path(forResource: resource, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? appResourceBundle
        return String(localized: key, bundle: bundle, locale: locale)
    }
}

extension BoxItem {
    func titleAndSubtitle() -> (title: String, subtitle: String, note: String?) {
        let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let meaningful = !cleaned.isEmpty && (kind == .text || kind == .link
            || ![kind.rawValue, kindTitle].contains { $0.caseInsensitiveCompare(cleaned) == .orderedSame })
        if !meaningful, kind != .link,
           let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            let lines = note.components(separatedBy: .newlines)
            let remainder = lines.dropFirst().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (lines[0].trimmingCharacters(in: .whitespaces), remainder,
                remainder.isEmpty ? nil : remainder)
        }
        let title: String
        if meaningful {
            if kind == .text {
                let first = cleaned.split(whereSeparator: \.isNewline).first.map(String.init) ?? cleaned
                title = first.count > 120 ? String(first.prefix(119)) + "…" : first
            } else { title = cleaned }
        } else { title = url ?? kindTitle }
        let subtitle: String
        if kind == .link { subtitle = url.flatMap { URL(string: $0)?.host } ?? url ?? "" }
        else if let note, !note.isEmpty { subtitle = note }
        else {
            subtitle = kind == .text ? (text ?? "").components(separatedBy: .newlines).dropFirst()
                .joined(separator: " ") : ""
        }
        return (title, subtitle, note.flatMap { $0.isEmpty ? nil : $0 })
    }
    var displayTitle: String { titleAndSubtitle().title }
    var authorTitle: String {
        switch author {
        case .boss: return L("Me")
        case let .agent(_, name):
            let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return cleaned.isEmpty ? L("Agents") : L("Agents") + " · " + cleaned
        }
    }
    var summary: String { titleAndSubtitle().subtitle }
    var detailNote: String? { titleAndSubtitle().note }
    var detailBody: String? {
        guard kind == .text, let text, !text.isEmpty, text != displayTitle else { return nil }
        return text
    }
    var sizeTitle: String? {
        mediaBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }
    var fileExtension: String {
        let ext = ((text ?? "") as NSString).pathExtension
        return (ext.isEmpty ? mediaType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
            ?? "" : ext).uppercased()
    }
    var durationTitle: String? {
        durationMs.map { String(format: "%d:%02d", $0 / 60_000, ($0 / 1000) % 60) }
    }
    var detailFormat: String? {
        let format = kind == .text || kind == .link ? kindTitle
            : (fileExtension.isEmpty ? nil : fileExtension)
        let dimensions = kind == .image ? imageDimensionsTitle : nil
        let duration = kind == .video ? durationTitle : nil
        let parts = [format, dimensions, duration, sizeTitle].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    private var imageDimensionsTitle: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }
    func metadata(now: Date) -> String {
        [kindTitle, sizeTitle, BoxTime.relative(createdAt, now: now), authorTitle, project]
            .compactMap { $0 }.joined(separator: " · ")
    }
    var deleteTitle: String { L("Delete “\(displayTitle)”?") }
}

extension BoxItem.Kind {
    var filterTitle: String {
        switch self {
        case .link: L("Links")
        case .text: L("Text")
        case .image: L("Images")
        case .video: L("Videos")
        case .file: L("Files")
        }
    }
}
