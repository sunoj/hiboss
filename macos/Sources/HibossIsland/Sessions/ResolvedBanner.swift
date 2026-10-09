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
        case .autoSelected: return L("Default picked · not approval")
        case .replied: return L("You replied")
        case .expired: return L("Expired without an answer")
        case .none:
            if message?.metadata?.isExpired == true, message?.defaultOption != nil {
                return L("Default picked · not approval")
            }
            if let status = message?.status, ["replied", "resolved"].contains(status) {
                return L("Resolved · answer unavailable")
            }
            return nil
        case .open: return nil
        }
    }

    private var recorded: Bool {
        switch outcome {
        case .chosen, .replied: true
        default: false
        }
    }

    var body: some View {
        if let title = Self.title(for: outcome, message: thread.message) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Label(title, systemImage: recorded ? "checkmark.circle" : "clock")
                    Spacer(minLength: 4)
                    if let date = thread.newestReply.flatMap({ ISODate.parse($0.createdAt) }) {
                        Text(date, format: .dateTime.hour().minute())
                    }
                }.font(.callout)
                if case let .autoSelected(option) = outcome, let option {
                    Text(option).font(.caption).textSelection(.enabled)
                }
                if case let .replied(text, _) = outcome {
                    Text(text).font(.body).textSelection(.enabled)
                }
                if recorded, let source = thread.newestReply?.metadata?.source {
                    Text(L("Answered on \(source.capitalized)")).font(.caption)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(recorded ? TodayStyle.settled : TodayStyle.secondary)
            .background(recorded ? TodayStyle.settledSoft : TodayStyle.ground,
                in: RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("session.resolved.\(thread.id.rawValue)")
        }
    }
}
