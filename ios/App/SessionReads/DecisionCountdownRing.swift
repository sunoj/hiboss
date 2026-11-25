// A ring that empties as a pending decision's timeout runs out, around the needs-you dot.
// Exports DecisionCountdownRing; past the deadline it settles into a plain needs-you dot.
// Dependencies: SwiftUI TimelineView, HibossKit DecisionWindow, and Theme's attention color.

import HibossKit
import SwiftUI

struct DecisionCountdownRing: View {
    let window: DecisionWindow

    private let side: CGFloat = 16
    private let line: CGFloat = 2.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = window.remainingFraction(at: context.date)
            ZStack {
                if window.isLive(at: context.date) {
                    Circle().stroke(Theme.warn.opacity(0.25), lineWidth: line)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(Theme.warn, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Circle().fill(Theme.warn).frame(width: 7, height: 7)
            }
            .frame(width: side, height: side)
            .accessibilityElement()
            .accessibilityLabel(label(at: context.date))
        }
    }

    private func label(at now: Date) -> Text {
        guard window.isLive(at: now) else { return Text("Needs you") }
        let left = Duration.seconds(Int(window.deadline.timeIntervalSince(now).rounded(.up))).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
        return Text("Needs you, \(left) left")
    }
}
