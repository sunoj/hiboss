// A live countdown to a deadline, ticking once per second until it expires.
// Exports: CountdownText view used on pending decision cards.
// Dependencies: SwiftUI TimelineView for tick scheduling.

import SwiftUI

struct CountdownText: View {
    let deadline: Date
    var tint: Color = Theme.ink2

    /// Under two minutes the clock reads as a live emergency, not metadata.
    private let urgentWindow: TimeInterval = 120
    /// Under five minutes it should still pull the eye.
    private let warnWindow: TimeInterval = 300

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = deadline.timeIntervalSince(context.date)
            Text(verbatim: remaining <= 0 ? String(localized: "Expired") : String(localized: "\(format(remaining)) left"))
                .monospacedDigit()
                .fontWeight(remaining > 0 && remaining <= warnWindow ? .semibold : .regular)
                .foregroundStyle(color(for: remaining))
        }
    }

    private func color(for remaining: TimeInterval) -> Color {
        if remaining <= 0 { return Theme.ink2 }
        if remaining <= urgentWindow { return Theme.negative }
        if remaining <= warnWindow { return Theme.warn }
        return tint
    }

    /// h:mm:ss for long windows, m:ss otherwise — never a bare minute overflow.
    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let pattern: Duration.TimeFormatStyle.Pattern = total >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(total).formatted(.time(pattern: pattern))
    }
}
