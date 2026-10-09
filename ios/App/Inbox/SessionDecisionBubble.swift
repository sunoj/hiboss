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
            if isPending {
                DecisionCard(message: message, submitting: store.replying[message.id],
                             header: DecisionCardInfo(message: message), choices: pendingOptions)
            } else {
                DecisionProvenance(message: message)
                SessionBubbleView(event: event, style: style, attachment: message.metadata?.attachment)
                OptionMediaComparison(options: message.options, media: message.metadata?.optionMedia ?? [],
                                      settlement: store.settlement(for: message.id))
                    .padding(.horizontal, 12)
                if let settlement = store.settlement(for: message.id) { answered(settlement) }
                if message.defaultOption != nil {
                    DecisionTimingView(timing: DecisionTiming(message: message), messageID: message.id)
                }
            }
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcript-decision-\(message.id.rawValue)")
    }

    private var isPending: Bool {
        (message.isPendingDecision || AttentionModel.needsTextReply(message, now: .now))
            && !store.withdrawn.contains(message.id)
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
