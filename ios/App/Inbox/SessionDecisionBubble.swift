// An agent decision inside the transcript: answerable in place while pending, answer once settled.
// Exports: SessionDecisionBubble. Uses the same timing line and options as the Home card.
// Dependencies: SwiftUI, HibossKit, SessionBubbleView, DecisionTimingView, DecisionOptions, InboxStore.

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
            SessionBubbleView(event: event, style: style)
            if isPending {
                pendingControls
            } else if let settlement = store.settlement(for: message.id) {
                answered(settlement)
            }
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transcript-decision-\(message.id.rawValue)")
    }

    private var isPending: Bool {
        message.isPendingDecision && !store.withdrawn.contains(message.id)
    }

    private var pendingControls: some View {
        let timing = DecisionTiming(message: message)
        return VStack(alignment: .leading, spacing: 10) {
            DecisionTimingView(timing: timing, messageID: message.id)
            DecisionOptions(options: message.options, timing: timing,
                            submitting: store.replying[message.id], onChoose: onChoose)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func answered(_ settlement: DecisionSettlement) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label { Text(verbatim: settlement.answer) } icon: { Image(systemName: settlement.symbol) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .symbolRenderingMode(.hierarchical)
            settlement.attribution
                .font(.caption)
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 12)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transcript-answer-\(message.id.rawValue)")
    }
}
