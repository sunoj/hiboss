// Compact remaining and elapsed clocks for attention rows.
// Exports: AttentionClock remaining/elapsed formatters and ElapsedLabelSchedule.
// Dependencies: Duration.UnitsFormatStyle for locale-correct unit names; SwiftUI TimelineSchedule.

import Foundation
import SwiftUI

enum AttentionClock {
    /// Ceil so a fraction of a second left still reads as 1s, not 0s.
    static func remaining(until date: Date, now: Date, locale: Locale = .autoupdatingCurrent) -> String {
        format(seconds: max(0, Int(ceil(date.timeIntervalSince(now)))), locale: locale)
    }

    static func elapsed(since date: Date, now: Date, coarse: Bool = false,
                        locale: Locale = .autoupdatingCurrent) -> String {
        format(seconds: max(0, Int(now.timeIntervalSince(date))), coarse: coarse, locale: locale)
    }

    /// Two adjacent units at most (5m 3s, 1h 1m, 3d 2h). The value is truncated to the
    /// smallest shown unit first, because the format style would otherwise round up.
    /// `coarse` drops the seconds after the first minute (5m), for labels that tick rarely.
    static func format(seconds: Int, coarse: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = switch seconds {
        case ..<60: [.seconds]
        case ..<3600: coarse ? [.minutes] : [.minutes, .seconds]
        case ..<(48 * 3600): [.hours, .minutes]
        default: [.days, .hours]
        }
        let step = step(seconds: seconds, coarse: coarse)
        var style = Duration.UnitsFormatStyle(
            allowedUnits: units, width: .narrow, maximumUnitCount: 2,
            zeroValueUnits: seconds < 60 ? .show(length: 1) : .hide
        )
        style.locale = locale
        return Duration.seconds(seconds / step * step).formatted(style)
    }

    /// The smallest unit `format` shows at this age, in seconds.
    static func step(seconds: Int, coarse: Bool = false) -> Int {
        switch seconds {
        case ..<60: 1
        case ..<3600: coarse ? 60 : 1
        case ..<(48 * 3600): 60
        default: 3600
        }
    }
}

/// Ticks only when a coarse elapsed label since `since` can change: each second in the first
/// minute, then on each whole minute or hour. A one-second ticker re-lays out the whole window.
struct ElapsedLabelSchedule: TimelineSchedule {
    let since: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = startDate
        return AnyIterator {
            let current = next
            let age = max(0, Int(current.timeIntervalSince(since)))
            let step = AttentionClock.step(seconds: age, coarse: true)
            next = since.addingTimeInterval(TimeInterval((age / step + 1) * step))
            return current
        }
    }
}
