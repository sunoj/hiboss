// Compact remaining and elapsed clocks for attention rows.
// Exports: AttentionClock remaining/elapsed formatters.
// Dependencies: Foundation Duration.UnitsFormatStyle for locale-correct unit names.

import Foundation

enum AttentionClock {
    /// Ceil so a fraction of a second left still reads as 1s, not 0s.
    static func remaining(until date: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        format(seconds: max(0, Int(ceil(date.timeIntervalSince(now)))), locale: locale)
    }

    static func elapsed(since date: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        format(seconds: max(0, Int(now.timeIntervalSince(date))), locale: locale)
    }

    /// Two adjacent units at most (5m 3s, 1h 1m, 3d 2h). The value is truncated to the
    /// smallest shown unit first, because the format style would otherwise round up.
    static func format(seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let (units, step): (Set<Duration.UnitsFormatStyle.Unit>, Int) = switch seconds {
        case ..<60: ([.seconds], 1)
        case ..<3600: ([.minutes, .seconds], 1)
        case ..<(48 * 3600): ([.hours, .minutes], 60)
        default: ([.days, .hours], 3600)
        }
        var style = Duration.UnitsFormatStyle(
            allowedUnits: units, width: .narrow, maximumUnitCount: 2,
            zeroValueUnits: seconds < 60 ? .show(length: 1) : .hide
        )
        style.locale = locale
        return Duration.seconds(seconds / step * step).formatted(style)
    }
}
