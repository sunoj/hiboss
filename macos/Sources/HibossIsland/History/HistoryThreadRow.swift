// Inline session message with readable text, in-place replies, and optional metadata.
// Exports: HistoryThreadRow for the stream and notification detail.
// Dependencies: SwiftUI, HibossKit, HistoryMessageBody, and thread decision/reply views.

import HibossKit
import SwiftUI

enum HistoryDetailSection: Hashable {
    case message, choices, metadata
}

enum HistoryDetailLayout {
    static let showsMetadataByDefault = false

    static func sections(hasChoices: Bool) -> [HistoryDetailSection] {
        hasChoices ? [.message, .choices, .metadata] : [.message, .metadata]
    }
}

struct HistoryThreadRow: View {
    let thread: MessageThread
    var decision: AttentionItem? = nil
    var usesV4 = false
    var sessionEntries = false
    var mergedMessages: [HistoryMessage] = []
    var answerability: AnswerableDecisions = .loading
    @ObservedObject var reply: AttentionReplyState
    @Binding var isExpanded: Bool
    let isSearching: Bool
    let onCollapse: () -> Void
    let onChoose: (String) async -> ReplyFeedback?
    @State private var now = Date()
    @State private var showsMetadata = HistoryDetailLayout.showsMetadataByDefault

    private var message: HistoryMessage { thread.message }

    private var content: HistoryReadingContent {
        HistoryReadingContent(message: message)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 12) {
                header
                ForEach(HistoryDetailLayout.sections(
                    hasChoices: message.isDecision), id: \.self) {
                    section($0)
                    if sessionEntries, $0 == .message { SessionReactionChips(message: message) }
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.message.\(message.id.rawValue)")
        .task(id: message.expiresAt) { await observeDeadline() }
    }

    @ViewBuilder
    private func section(_ section: HistoryDetailSection) -> some View {
        switch section {
        case .message:
            if usesV4, let decision, answerability.state(for: message.id) == .open {
                TodayDecisionCard(item: decision, now: now, isSelected: false,
                    isSubmitting: reply.submitting.contains(message.id),
                    error: reply.errors[message.id]?.choiceText,
                    onSelect: { showsMetadata.toggle() }, onChoose: { text in
                        Task { await reply.send(text, for: message.id) { choice, _ in
                            await onChoose(choice)
                        } }
                    })
                if let attachment = content.attachment { MessageAttachmentView(attachment: attachment) }
                HistoryReplyActions(message: message, reply: reply,
                    answerability: answerability, onChoose: onChoose)
            } else {
                HistoryMessageBody(content: content, isSearching: isSearching,
                    isExpanded: $isExpanded, onCollapse: onCollapse)
            }
        case .choices:
            choices
        case .metadata:
            if sessionEntries {
                if SessionThreadLogic.hasDetails(message) { metadata }
                SessionThreadEntries(thread: thread, merged: mergedMessages)
            } else {
                if !visibleReplies.isEmpty { HistoryReplies(replies: visibleReplies).equatable() }
                metadata
            }
        }
    }

    @ViewBuilder
    private var choices: some View {
        if usesV4 {
            if decision == nil || answerability.state(for: message.id) != .open {
                let outcome = answerability.outcome(for: thread, at: now)
                if !sessionEntries || thread.replies.isEmpty {
                    ResolvedBanner(thread: thread, outcome: outcome)
                }
                if let media = HistoryOptionSelection.selectedMedia(
                    in: message.metadata, outcome: outcome) {
                    HistoryChosenOptionImage(media: media)
                }
                DisclosureGroup(L("Decision options")) {
                    HistoryDecisionBlock(thread: thread,
                        reply: reply, answerability: answerability, onChoose: onChoose)
                }.font(.callout)
            }
        } else {
            HistoryDecisionBlock(thread: thread,
                reply: reply, answerability: answerability, onChoose: onChoose)
        }
    }

    private var visibleReplies: [HistoryMessage] {
        switch thread.outcome(at: now) {
        case .chosen, .autoSelected:
            thread.replies.filter { $0.id != thread.newestReply?.id }
        default:
            thread.replies
        }
    }

    @ViewBuilder private var avatar: some View {
        if message.isBossHistoryMessage {
            Text(message.historyMonogram).font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
        } else {
            AgentAvatarView(name: message.agentName ?? message.historyDisplayName, size: 34,
                            lookupName: message.agentName)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sender
                Spacer(minLength: 12)
                timestamp.frame(width: 160, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 4) {
                sender
                timestamp
            }
        }
    }

    private var sender: some View {
        HStack(spacing: 6) {
            Text(message.historyDisplayName).font(.headline)
            if message.isUnreadHistoryMessage {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).accessibilityLabel(L("Unread"))
            }
            if let glyph = message.historyPriorityGlyph {
                Image(systemName: glyph).foregroundStyle(.secondary)
                    .accessibilityLabel(message.historyPriorityAccessibilityLabel)
            }
        }
    }

    private var timestamp: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            Text(HistoryTimestamp.date(from: message.createdAt).map {
                SharedTimestamp.string($0, now: tick.date)
            } ?? L("Unknown"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var metadata: some View {
        DisclosureGroup(L("Details"), isExpanded: $showsMetadata) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Status") + ": " + message.status)
                Text(L("Priority") + ": " + message.priority)
                if let channel = message.channel { Text(L("Channel") + ": " + channel) }
                if let mode = message.mode { Text(L("Mode") + ": " + mode) }
                ForEach(message.metadata?.files ?? [], id: \.self) { Text($0) }
            }
            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func observeDeadline() async {
        now = .now
        guard let deadline = message.expirationDate, deadline > now else { return }
        do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
        catch { return }
        now = .now
    }
}
