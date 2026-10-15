// One chronological conversation card, including boss answers and agent follow-ups.
// Exports SessionThreadCard and SessionConversation; uses shared decision controls and reactions.

import HibossKit
import SwiftUI

struct SessionConversation: View {
    let messages: [HistoryMessage]
    @ObservedObject var store: InboxStore
    let sessionAgent: String?
    let onChoose: (String, MessageID) -> Void

    private var layout: SessionThreads {
        SessionThreads(messages: messages, isOpen: { store.answerability(for: $0) == .open })
    }

    var body: some View {
        let presentation = layout
        VStack(alignment: .leading, spacing: 12) {
            if !presentation.needsYou.isEmpty {
                Text("Needs you").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(presentation.needsYou) { thread in
                    pendingThread(thread)
                }
            }
            if !presentation.conversation.isEmpty {
                Text("Conversation").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(Array(presentation.conversation.enumerated()), id: \.element.id) { index, card in
                    if index == 0 || !Calendar.current.isDate(card.lastActivity,
                        inSameDayAs: presentation.conversation[index - 1].lastActivity) {
                        dayLabel(card.lastActivity)
                    }
                    SessionThreadCard(card: card, store: store)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func pendingThread(_ thread: MessageThread) -> some View {
        if thread.entries.isEmpty {
            pendingDecision(thread)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                pendingDecision(thread)
                ForEach(thread.entries) { entry in
                    SessionThreadCard(card: .init(threads: [thread]), store: store)
                        .entryRow(entry, root: thread.message)
                        .padding(.leading, 16).padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("needs-thread-\(thread.id.rawValue)")
        }
    }

    private func pendingDecision(_ thread: MessageThread) -> some View {
        SessionDecisionBubble(event: event(thread.message), style: style,
                              message: thread.message, store: store,
                              sessionAgent: sessionAgent) { onChoose($0, thread.id) }
    }

    private var style: SessionBubbleStyle {
        SessionBubbleStyle(isOutgoing: false, isFirstInGroup: true, isLastInGroup: true, showsSender: false)
    }

    private func event(_ message: HistoryMessage) -> SessionEvent {
        SessionEvent(id: message.id.rawValue, sessionId: message.sessionId ?? "", sequence: 0,
                     kind: "message", direction: message.direction, actorName: message.agentName,
                     messageId: message.id.rawValue, payload: .object(["body": .string(message.body)]),
                     createdAt: message.createdAt)
    }

    private func dayLabel(_ date: Date) -> some View {
        Group {
            if Calendar.current.isDateInToday(date) { Text("Today") }
            else if Calendar.current.isDateInYesterday(date) { Text("Yesterday") }
            else { Text(date, format: .dateTime.month(.abbreviated).day()) }
        }.font(.caption).foregroundStyle(Theme.ink2).accessibilityAddTraits(.isHeader)
    }
}

struct SessionThreadCard: View {
    let card: SessionThreads.Card
    @ObservedObject var store: InboxStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                if !card.threads[0].isBoss {
                    AgentAvatarView(name: card.threads[0].message.displayName, size: 32,
                                    lookupName: card.threads[0].message.agentName)
                }
                Text(verbatim: card.threads[0].isBoss
                    ? String(localized: "You") : card.threads[0].message.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            ForEach(card.threads) { thread in
                messageRow(thread.message)
                OptionMediaComparison(options: thread.message.options,
                                      media: thread.message.metadata?.optionMedia ?? [],
                                      metadata: thread.message.metadata,
                                      settlement: store.settlement(for: thread.id))
                ForEach(thread.entries) { entry in
                    entryRow(entry, root: thread.message).padding(.leading, 16)
                }
                if thread.replies.isEmpty, let settlement = store.settlement(for: thread.id) {
                    ResolvedBanner(settlement: settlement, date: nil)
                        .accessibilityIdentifier("transcript-answer-\(thread.id.rawValue)")
                } else if thread.replies.isEmpty, thread.message.isDecision,
                          let label = store.answerability(for: thread.id).label {
                    Text(verbatim: label).font(.footnote).foregroundStyle(Theme.ink2)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(card.threads[0].message.isDecision
            ? "transcript-decision-\(card.id.rawValue)" : "thread-\(card.id.rawValue)")
    }

    @ViewBuilder fileprivate func entryRow(_ entry: HistoryMessage, root: HistoryMessage) -> some View {
        if entry.direction == "boss_to_agent", let settlement = settlement(entry, root: root) {
            VStack(alignment: .leading, spacing: 6) {
                ResolvedBanner(settlement: settlement, date: entry.createdDate,
                               optionDescription: root.metadata?.optionDescription(for: entry.body))
                    .accessibilityIdentifier("transcript-answer-\(root.id.rawValue)")
                if let attachment = entry.metadata?.attachment {
                    MessageAttachmentView(attachment: attachment)
                }
                MessageReactions(message: entry)
                ThreadMessageDetails(message: entry)
            }.accessibilityElement(children: .contain)
                .accessibilityIdentifier("session-bubble-outgoing")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if entry.agentName != root.agentName {
                    Text(verbatim: entry.displayName).font(.caption.weight(.semibold))
                }
                messageRow(entry)
            }.accessibilityElement(children: .contain)
                .accessibilityIdentifier("followup-\(entry.id.rawValue)")
        }
    }

    private func messageRow(_ message: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: message.body).font(.subheadline).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let attachment = message.metadata?.attachment {
                MessageAttachmentView(attachment: attachment)
            }
            MessageReactions(message: message)
            if let date = message.createdDate {
                RecordedTimeText(date: date).font(.caption).foregroundStyle(Theme.ink2)
            }
            ThreadMessageDetails(message: message)
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("session-bubble-incoming")
    }

    private func settlement(_ reply: HistoryMessage, root: HistoryMessage) -> DecisionSettlement? {
        var result = DecisionSettlement(reply: reply)
        if root.metadata?.isExpired == true { result?.isAutoDefault = true }
        return result
    }
}

private struct ThreadMessageDetails: View {
    let message: HistoryMessage

    var body: some View {
        if SessionThreads.hasDetails(message) {
            DisclosureGroup {
                if let content = message.content, content != message.body {
                    MediaMarkdownView(content).font(.subheadline)
                }
                ForEach(message.metadata?.files ?? [], id: \.self) { file in
                    Text(verbatim: file).font(.footnote)
                }
            } label: {
                Text("Details").frame(minHeight: 44, alignment: .leading)
            }
        }
    }
}
