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
    var sessionAgent: String? = nil
    let onChoose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.answerability(for: message.id) == .open {
                DecisionCard(message: message, submitting: store.replying[message.id],
                             verifying: store.replyGate.verifying.contains(message.id),
                             verificationTimedOut: store.replyGate.verificationTimedOut.contains(message.id),
                             header: SessionDecisionHeader(message: message, sessionAgent: sessionAgent),
                             choices: pendingOptions)
            } else {
                if let agent = differingAgent {
                    Text(verbatim: agent).font(.caption).foregroundStyle(Theme.ink2)
                }
                SessionBubbleView(event: event, style: resolvedStyle,
                                  attachment: message.metadata?.attachment,
                                  content: message.content)
                OptionMediaComparison(options: message.options, media: message.metadata?.optionMedia ?? [],
                                      metadata: message.metadata,
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
        DecisionOptions(options: message.options, metadata: message.metadata,
                        timing: DecisionTiming(message: message),
                        submitting: store.replying[message.id],
                        locksControls: store.replyGate.locksControls(for: message.id),
                        wrapsToFit: true, onChoose: onChoose)
    }

    private var differingAgent: String? {
        message.agentName == sessionAgent ? nil : message.agentName
    }

    private var resolvedStyle: SessionBubbleStyle {
        var result = style
        result.showsSender = false
        return result
    }

    private func answered(_ settlement: DecisionSettlement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ResolvedBanner(settlement: settlement, date: store.reply(to: message.id)?.createdDate)
            OptionDescriptionText(text: message.metadata?.optionDescription(for: settlement.answer))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transcript-answer-\(message.id.rawValue)")
    }
}

// The session owns provenance; each card keeps its question, evidence and deadline.
private struct SessionDecisionHeader: View {
    let message: HistoryMessage
    let sessionAgent: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                if let agent = message.agentName, agent != sessionAgent {
                    Text(verbatim: agent).font(.caption).foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 8)
                if let deadline = message.expirationDate {
                    CountdownText(deadline: deadline, tint: Theme.warn).font(.footnote)
                } else {
                    Text("No deadline").font(.footnote).foregroundStyle(Theme.ink3)
                }
            }
            Text(verbatim: message.messageText.title).font(.headline).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let content = message.messageText.content,
               !content.isEmpty,
               content != message.body.trimmingCharacters(in: .whitespacesAndNewlines) {
                MediaMarkdownView(content).font(.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
