// A live countdown to a deadline, ticking once per second until it expires.
// Exports: CountdownText view used on pending decision cards.
// Dependencies: SwiftUI TimelineView for tick scheduling.

import SwiftUI

struct CountdownText: View {
    let deadline: Date
    var tint: Color = .secondary

    /// Under two minutes the clock reads as a live emergency, not metadata.
    private let urgentWindow: TimeInterval = 120
    /// Under five minutes it should still pull the eye.
    private let warnWindow: TimeInterval = 300

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = deadline.timeIntervalSince(context.date)
            Text(remaining <= 0 ? "Expired" : "\(format(remaining)) left")
                .monospacedDigit()
                .fontWeight(remaining > 0 && remaining <= warnWindow ? .semibold : .regular)
                .foregroundStyle(color(for: remaining))
        }
    }

    private func color(for remaining: TimeInterval) -> Color {
        if remaining <= 0 { return .secondary }
        if remaining <= urgentWindow { return .red }
        if remaining <= warnWindow { return .orange }
        return tint
    }

    /// h:mm:ss for long windows, m:ss otherwise — never a bare minute overflow.
    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
