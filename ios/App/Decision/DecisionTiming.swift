// Shared timing presentation for a pending decision: auto-default countdown or wait time.
// Exports: DecisionTiming (pure projection) and DecisionTimingView, used by Home and detail.
// Dependencies: SwiftUI, HibossKit HistoryMessage, CountdownText.

import HibossKit
import SwiftUI

/// One reading of a message's clock, so Home and detail never word it differently.
struct DecisionTiming: Equatable {
    let deadline: Date?
    let expiresAt: Date?
    let createdAt: Date?
    /// The option the server picks on timeout — only while a live expiration exists.
    let autoDefault: String?
    let declaredDefault: String?

    init(message: HistoryMessage, now: Date = Date()) {
        let live = message.expirationDate.flatMap { $0 > now ? $0 : nil }
        let trimmed = message.defaultOption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        deadline = message.expirationDate
        expiresAt = live
        createdAt = message.createdDate
        declaredDefault = trimmed.isEmpty ? nil : message.defaultOption
        autoDefault = live != nil && !trimmed.isEmpty ? message.defaultOption : nil
    }

    /// The only moments the projection can change: now, and the live deadline passing.
    static func refreshDates(for message: HistoryMessage, now: Date = Date()) -> [Date] {
        [now] + [message.expirationDate].compactMap { $0 }.filter { $0 > now }
    }

    /// Whether an agent option is the live timeout default (trim-normalized).
    func isAutoDefault(_ option: String) -> Bool {
        autoDefault != nil && option.trimmingCharacters(in: .whitespacesAndNewlines)
            == autoDefault?.trimmingCharacters(in: .whitespacesAndNewlines)
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
    var compact: Bool = false
    var showsNoDeadline: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if timing.deadline == nil && showsNoDeadline { Text("No deadline") }
            if let option = timing.declaredDefault {
                TimelineView(.everyMinute) { context in
                    let time = timing.deadline.map { deadline in
                        Duration.seconds(max(0, deadline.timeIntervalSince(context.date))).formatted(
                            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated,
                                   maximumUnitCount: 1)
                        )
                    } ?? String(localized: "an unspecified time")
                    Text("No answer in \(time) picks “\(option)”. That is not approval.")
                }
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
        .font(compact ? .hbCaption : .hbCallout)
        .foregroundStyle(Theme.ink2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("decision-timing-\(messageID.rawValue)")
    }

}
