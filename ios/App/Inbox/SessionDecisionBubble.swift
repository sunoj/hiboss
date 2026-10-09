// An agent decision inside the transcript: answerable in place while pending, answer once settled.
// Exports: SessionDecisionBubble. Pending decisions use Today's shared DecisionCard.
// Dependencies: SwiftUI, HibossKit, DecisionCard, SessionBubbleView, and InboxStore.

import HibossKit
import SwiftUI

struct SessionDecisionBubble: View {
    let event: SessionEvent
    let style: SessionBubbleStyle
    let message: HistoryMessage
    @ObservedObject var store: InboxStore
    let onChoose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.answerability(for: message.id) == .open {
                DecisionCard(message: message, submitting: store.replying[message.id],
                             header: DecisionCardInfo(message: message), choices: pendingOptions)
            } else {
                DecisionProvenance(message: message)
                SessionBubbleView(event: event, style: style, attachment: message.metadata?.attachment)
                OptionMediaComparison(options: message.options, media: message.metadata?.optionMedia ?? [],
                                      settlement: store.settlement(for: message.id))
                    .padding(.horizontal, 12)
                if let settlement = store.settlement(for: message.id) { answered(settlement) }
                else if let label = store.answerability(for: message.id).label {
                    Text(verbatim: label).font(.footnote).foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcript-decision-\(message.id.rawValue)")
    }

    private var pendingOptions: some View {
        DecisionOptions(options: message.options, timing: DecisionTiming(message: message),
                        submitting: store.replying[message.id], wrapsToFit: true, onChoose: onChoose)
    }

    private func answered(_ settlement: DecisionSettlement) -> some View {
        ResolvedBanner(settlement: settlement, date: store.reply(to: message.id)?.createdDate)
        .accessibilityIdentifier("transcript-answer-\(message.id.rawValue)")
    }
}
