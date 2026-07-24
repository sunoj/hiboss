// A live countdown to a deadline, ticking once per second until it expires.
// Exports: CountdownText view used on pending decision cards.
// Dependencies: SwiftUI TimelineView for tick scheduling.

import SwiftUI

struct CountdownText: View {
    let deadline: Date
    var tint: Color = .secondary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = deadline.timeIntervalSince(context.date)
            Text(remaining <= 0 ? "Expired" : "\(format(remaining)) left")
                .monospacedDigit()
                .foregroundStyle(remaining <= 0 ? .secondary : tint)
        }
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
