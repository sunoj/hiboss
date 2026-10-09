// An agent decision inside the transcript: answerable in place while pending, answer once settled.
// Exports: SessionDecisionBubble. Shares timing, options and media with the Home and detail surfaces.
// Dependencies: SwiftUI, HibossKit, SessionBubbleView, DecisionTimingView, DecisionOptions, InboxStore.

import HibossKit
import SwiftUI

struct SessionDecisionBubble: View {
    let event: SessionEvent
    let style: SessionBubbleStyle
    let message: HistoryMessage
    @ObservedObject var store: InboxStore
    let onChoose: (String) -> Void
    @State private var draft = ""
    @Environment(\.openConnectionSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DecisionProvenance(message: message)
            SessionBubbleView(event: event, style: style, attachment: message.metadata?.attachment)
            OptionMediaComparison(
                options: message.options,
                media: message.metadata?.optionMedia ?? [],
                settlement: isPending ? nil : store.settlement(for: message.id)
            )
            .padding(.horizontal, 12)
            if isPending {
                pendingControls
            } else {
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

    private var pendingControls: some View {
        let timing = DecisionTiming(message: message)
        return VStack(alignment: .leading, spacing: 10) {
            DecisionTimingView(timing: timing, messageID: message.id)
            if let content = message.content, !content.isEmpty {
                Text(verbatim: content).font(.subheadline).textSelection(.enabled)
            }
            DecisionOptions(options: message.options, timing: timing,
                            submitting: store.replying[message.id], onChoose: onChoose)
            HStack {
                TextField("Reply…", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                Button("Send") { onChoose(draft) }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || store.replying[message.id] != nil)
            }
            if store.replying[message.id] != nil { ReplyPendingNote(onSettings: openSettings) }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func answered(_ settlement: DecisionSettlement) -> some View {
        ResolvedBanner(settlement: settlement, date: store.reply(to: message.id)?.createdDate)
        .accessibilityIdentifier("transcript-answer-\(message.id.rawValue)")
    }
}
