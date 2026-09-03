// Compact remaining and elapsed clocks for attention rows.
// Exports: AttentionClock remaining/elapsed formatters.
// Dependencies: Foundation.

import Foundation

enum AttentionClock {
    /// Ceil so a fraction of a second left still reads as 1s, not 0s.
    static func remaining(until date: Date, now: Date) -> String {
        format(seconds: max(0, Int(ceil(date.timeIntervalSince(now)))))
    }

    static func elapsed(since date: Date, now: Date) -> String {
        format(seconds: max(0, Int(now.timeIntervalSince(date))))
    }

    static func format(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 {
            let remainder = seconds % 60
            return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
        }
        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        if hours < 48 {
            return remainderMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainderMinutes)m"
        }
        let days = hours / 24
        let remainderHours = hours % 24
        return remainderHours == 0 ? "\(days)d" : "\(days)d \(remainderHours)h"
    }
}
