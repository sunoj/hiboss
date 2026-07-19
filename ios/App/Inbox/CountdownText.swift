// A live m:ss countdown to a deadline, ticking once per second.
// Exports: CountdownText view used on pending decision cards.
// Dependencies: SwiftUI TimelineView for tick scheduling.

import SwiftUI

struct CountdownText: View {
    let deadline: Date
    var tint: Color = Theme.ink2

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .medium))
                Text("\(format(remaining)) left")
            }
            .font(.hbMonoSmall)
            .foregroundStyle(tint)
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
