// Shared timing presentation for a pending decision: auto-default countdown or wait time.
// Exports: DecisionTiming (pure projection) and DecisionTimingView, used by Home and detail.
// Dependencies: SwiftUI, HibossKit HistoryMessage, CountdownText.

import HibossKit
import SwiftUI

/// One reading of a message's clock, so Home and detail never word it differently.
struct DecisionTiming: Equatable {
    let expiresAt: Date?
    let createdAt: Date?
    /// The option the server picks on timeout — only while a live expiration exists.
    let autoDefault: String?

    init(message: HistoryMessage, now: Date = Date()) {
        let live = message.expirationDate.flatMap { $0 > now ? $0 : nil }
        let trimmed = message.defaultOption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        expiresAt = live
        createdAt = message.createdDate
        autoDefault = live != nil && !trimmed.isEmpty ? message.defaultOption : nil
    }

    /// Whether an agent option is the live timeout default (trim-normalized).
    func isAutoDefault(_ option: String) -> Bool {
        autoDefault != nil && option.trimmingCharacters(in: .whitespacesAndNewlines) == autoDefault?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Waiting 3 min" — a duration, not a relative date, so it reads naturally in every locale.
    static func waitedText(since created: Date?, now: Date) -> Text {
        guard let created else { return Text("Waiting") }
        let seconds = max(Int(now.timeIntervalSince(created)), 0)
        let waited = Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1)
        )
        return Text("Waiting \(waited)")
    }
}

struct DecisionTimingView: View {
    let timing: DecisionTiming
    let messageID: MessageID

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let deadline = timing.expiresAt, let option = timing.autoDefault {
                Label {
                    Text("Auto-selects “\(option)” when time runs out")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                Label { CountdownText(deadline: deadline) } icon: { Image(systemName: "timer") }
            } else {
                TimelineView(.everyMinute) { context in
                    Label { DecisionTiming.waitedText(since: timing.createdAt, now: context.date) } icon: {
                        Image(systemName: "hourglass")
                    }
                }
                if let deadline = timing.expiresAt {
                    Label {
                        Text("Reply by \(deadline.formatted(date: .abbreviated, time: .shortened))")
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                }
            }
        }
        .font(.hbCallout)
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("decision-timing-\(messageID.rawValue)")
    }
}
