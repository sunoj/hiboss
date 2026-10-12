// Localized Box metadata and recency grouping used by rows, detail and viewer captions.
// Exports BoxItem presentation helpers and BoxDayGroup.
// Dependencies: SwiftUI, HibossKit and the shared ISO timestamp parser.

import HibossKit
import Foundation

extension BoxItem {
    var provenanceLabel: String? {
        guard case let .agent(_, name) = author else { return nil }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return String(localized: "Agents")
        }
        return String(localized: "Agents · \(name)")
    }

    var boxTitle: String {
        if let text, !text.isEmpty { return text }
        return url ?? note ?? kindLabel
    }

    var kindLabel: String {
        switch kind {
        case .link: String(localized: "Link")
        case .text: String(localized: "Text")
        case .image: String(localized: "Image")
        case .video: String(localized: "Video")
        case .file: String(localized: "File")
        }
    }

    var symbol: String {
        switch kind {
        case .link: "globe"
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "video"
        case .file: "doc"
        }
    }

    var authorLabel: String { provenanceLabel ?? String(localized: "Me") }

    var sizeLabel: String? {
        mediaBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
    }

    var formatLabel: String { mediaType ?? kindLabel }

    var durationLabel: String? {
        guard let durationMs else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: Double(durationMs) / 1000)
    }

    var relativeTime: String? {
        relativeTime(now: .now)
    }

    func relativeTime(now: Date, locale: Locale = .current, calendar: Calendar = .current) -> String? {
        guard let date = ISOTimestamp.date(from: createdAt) else { return nil }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.timeStyle = .short
            if locale.language.languageCode?.identifier == "zh" { formatter.dateFormat = "HH:mm" }
            let time = formatter.string(from: date)
            let appBundle = Bundle(identifier: "ai.hiboss.app") ?? .main
            let localization = Bundle.preferredLocalizations(
                from: appBundle.localizations, forPreferences: [locale.identifier]
            ).first
            let localizationBundle = localization
                .flatMap { appBundle.path(forResource: $0, ofType: "lproj") }
                .flatMap(Bundle.init(path:)) ?? appBundle
            let label = localizationBundle.localizedString(forKey: "Yesterday", value: nil, table: nil)
            return "\(label) \(time)"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        let label = formatter.localizedString(for: date, relativeTo: now)
        guard locale.language.languageCode?.identifier == "zh" else { return label }
        return label.replacingOccurrences(of: "秒钟", with: "秒")
            .replacingOccurrences(of: "(\\d+)\\s*(秒|分钟)", with: "$1 $2", options: .regularExpression)
    }

    var metadata: String {
        [kindLabel, sizeLabel, relativeTime, authorLabel, project]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var summary: String? {
        kind == .link ? url.flatMap { URL(string: $0)?.host } : note
    }

    var fileExtension: String {
        ((text ?? "") as NSString).pathExtension.uppercased()
    }
}

enum BoxDayGroup: CaseIterable {
    case today, yesterday, week, earlier

    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .week: String(localized: "This week")
        case .earlier: String(localized: "Earlier")
        }
    }

    static func group(_ item: BoxItem, now: Date = .now, calendar: Calendar = .current) -> Self {
        guard let date = ISOTimestamp.date(from: item.createdAt) else { return .earlier }
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .week }
        return .earlier
    }
}
