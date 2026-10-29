// Bounded memoization of Box row metadata until its displayed timestamp can change.
// Exports: BoxMetadataCache; entries include the item, locale and calendar to avoid stale labels.
// Dependencies: Foundation, HibossKit and the existing BoxItem presentation helpers.

import Foundation
import HibossKit

enum BoxMetadataCache {
    nonisolated(unsafe) private static let entries: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 2_000
        return cache
    }()

    static func value(for item: BoxItem, now: Date, build: () -> String) -> String {
        let calendar = Calendar.current
        let locale = Locale.current
        let key = item.id as NSString
        if let entry = entries.object(forKey: key), entry.item == item,
           entry.calendar == calendar, entry.locale == locale,
           entry.validity.contains(now) {
            return entry.value
        }
        let value = build()
        entries.setObject(Entry(item: item, calendar: calendar, locale: locale,
            validity: validity(for: item.createdAt, now: now, calendar: calendar), value: value), forKey: key)
        return value
    }

    private static func validity(for timestamp: String, now: Date, calendar: Calendar) -> Range<Date> {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(1)
        guard let date = ISODate.parse(timestamp) else { return now..<tomorrow }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 0 { return now..<min(date, tomorrow) }
        if elapsed < 12 * 3600 {
            let nextMinute = date.addingTimeInterval((floor(elapsed / 60) + 1) * 60)
            return now..<nextMinute
        }
        return now..<tomorrow
    }

    private final class Entry {
        let item: BoxItem
        let calendar: Calendar
        let locale: Locale
        let validity: Range<Date>
        let value: String

        init(item: BoxItem, calendar: Calendar, locale: Locale, validity: Range<Date>, value: String) {
            self.item = item
            self.calendar = calendar
            self.locale = locale
            self.validity = validity
            self.value = value
        }
    }
}
