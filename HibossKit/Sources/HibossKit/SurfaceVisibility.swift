// Lets a host pause clock-driven redraws while its window is closed, minimized or covered.
// Exports: EnvironmentValues.surfaceIsVisible and TimelineSchedule.paused(_:).
// Dependencies: SwiftUI TimelineSchedule; hosts that never set the value keep ticking.

import SwiftUI

public extension EnvironmentValues {
    /// False while the hosting window is off screen; each clock tick re-lays out that window.
    @Entry var surfaceIsVisible = true
}

/// A paused schedule yields only its start date, so the view shows the current time once
/// and stops; un-pausing installs a new schedule that resumes from that moment.
public struct PausableTimelineSchedule<Base: TimelineSchedule>: TimelineSchedule {
    let base: Base
    let isPaused: Bool

    public func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        guard !isPaused else { return AnyIterator(CollectionOfOne(startDate).makeIterator()) }
        var entries = base.entries(from: startDate, mode: mode).makeIterator()
        return AnyIterator { entries.next() }
    }
}

public extension TimelineSchedule {
    func paused(_ isPaused: Bool) -> PausableTimelineSchedule<Self> {
        PausableTimelineSchedule(base: self, isPaused: isPaused)
    }
}
