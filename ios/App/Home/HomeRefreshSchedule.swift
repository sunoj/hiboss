// When Home re-ranks: at each upcoming deadline, otherwise once a minute.
// Exports: HomeRefreshSchedule, a TimelineSchedule over known expiry dates.
// Dependencies: SwiftUI. Countdown rows keep their own one-second timelines.

import SwiftUI

struct HomeRefreshSchedule: TimelineSchedule {
    /// Moments the ranking changes on its own: a decision or request expiring.
    let deadlines: [Date]
    var fallback: TimeInterval = 60

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let upcoming = deadlines.filter { $0 > startDate }.sorted()
        var next: Date? = startDate
        var index = 0
        return AnyIterator {
            guard let current = next else { return nil }
            while index < upcoming.count, upcoming[index] <= current { index += 1 }
            let periodic = current.addingTimeInterval(fallback)
            // Re-rank just after a deadline passes, so the expired item has left.
            let deadline = index < upcoming.count ? upcoming[index].addingTimeInterval(0.5) : periodic
            next = min(deadline, periodic)
            return current
        }
    }
}
