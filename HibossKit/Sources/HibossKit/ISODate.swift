// Memoized parsing of server timestamps (ISO 8601 or SQLite UTC) read on every render.
// Exports: ISODate.parse — each distinct string is parsed once per process.
// Dependencies: Foundation (date formatters parse thread-safely; NSCache is too).

import Foundation

public enum ISODate {
    // NSCache and ISO8601DateFormatter are documented thread-safe, so shared statics are sound.
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSDate> = {
        let cache = NSCache<NSString, NSDate>()
        cache.countLimit = 20_000
        return cache
    }()
    /// Sentinel for strings that do not parse, so failures are not retried per render.
    nonisolated(unsafe) private static let invalid = NSDate(timeIntervalSince1970: -.greatestFiniteMagnitude)
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let whole: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let sqlite: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Parses `2026-09-30T08:00:00Z`, with or without fractional seconds, and SQLite's
    /// `2026-09-30 08:00:00`, which the server stores in UTC.
    public static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let key = value as NSString
        if let hit = cache.object(forKey: key) { return hit === invalid ? nil : hit as Date }
        let parsed = whole.date(from: value) ?? fractional.date(from: value) ?? sqlite.date(from: value)
        cache.setObject(parsed.map { $0 as NSDate } ?? invalid, forKey: key)
        return parsed
    }
}
