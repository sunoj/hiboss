// Recorded decision outcomes with a neutral, explicit timeout-default label.
// Exports: ResolvedBanner; unknown settlement never claims a boss answer.
// Dependencies: SwiftUI, HibossKit MessageThread, and design-v4 colours.

import HibossKit
import SwiftUI

struct ResolvedBanner: View {
    let thread: MessageThread
    let outcome: ThreadOutcome

    static func title(for outcome: ThreadOutcome, message: HistoryMessage? = nil) -> String? {
        switch outcome {
        case let .chosen(option, _): return L("You chose \(option)")
        case .autoSelected: return AnswerAttribution.defaultPicked
        case .replied: return L("You replied")
        case .expired: return L("Expired without an answer")
        case .none:
            if message?.metadata?.isExpired == true, message?.defaultOption != nil {
                return AnswerAttribution.defaultPicked
            }
            if let status = message?.status, ["replied", "resolved"].contains(status) {
                return L("Resolved · answer unavailable")
            }
            return nil
        case .open: return nil
        }
    }

    private var selectedDescription: String? {
        switch outcome {
        case let .chosen(option, _), let .autoSelected(option?):
            thread.message.metadata?.optionDescription(for: option)
        default: nil
        }
    }

    private var recorded: Bool {
        switch outcome {
        case .chosen, .replied: true
        default: false
        }
    }

    /// Where the answer came from; this Mac is left unnamed.
    private var source: String? {
        guard recorded else { return nil }
        return thread.newestReply?.metadata?.answeredBy?.displayLabel
            ?? AnswerSource.visibleLabel(thread.newestReply?.metadata?.source, hiding: "macos")
    }

    /// One line: how it ended, then where. The time follows in the same line.
    static func line(title: String, source: String?) -> String {
        ([title] + [source.map(AnswerAttribution.answeredOn)].compactMap { $0 }).joined(separator: " · ")
    }

    var body: some View {
        if let title = Self.title(for: outcome, message: thread.message) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Label(Self.line(title: title, source: source),
                        systemImage: recorded ? "checkmark.circle" : "clock")
                    if let date = thread.newestReply.flatMap({ ISODate.parse($0.createdAt) }) {
                        TimelineView(.periodic(from: .now, by: 60)) { tick in
                            Text(verbatim: " · " + SharedTimestamp.string(date, now: tick.date))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                if case let .autoSelected(option) = outcome, let option {
                    Text(option).font(.caption).textSelection(.enabled)
                }
                if case let .replied(text, _) = outcome {
                    Text(text).font(.body).textSelection(.enabled)
                }
                OptionDescriptionText(text: selectedDescription)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(recorded ? TodayStyle.settled : TodayStyle.secondary)
            .background(recorded ? TodayStyle.settledSoft : TodayStyle.ground,
                in: RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("session.resolved.\(thread.id.rawValue)")
        }
    }
}
