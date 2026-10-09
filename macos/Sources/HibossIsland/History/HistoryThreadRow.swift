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
                ForEach(HistoryDetailLayout.sections(hasChoices: !message.options.isEmpty), id: \.self) {
                    section($0)
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
            HistoryMessageBody(content: content, isSearching: isSearching,
                isExpanded: $isExpanded, onCollapse: onCollapse)
        case .choices:
            HistoryDecisionBlock(thread: thread, outcome: thread.outcome(at: now),
                reply: reply, onChoose: onChoose)
        case .metadata:
            if !visibleReplies.isEmpty { HistoryReplies(replies: visibleReplies) }
            metadata
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

    private var avatar: some View {
        Text(message.historyMonogram).font(.callout.weight(.semibold))
            .foregroundStyle(message.isBossHistoryMessage ? Color.accentColor : .secondary)
            .frame(width: 34, height: 34)
            .background(message.isBossHistoryMessage
                ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                sender
                Spacer(minLength: 12)
                timestamp
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
        Text(HistoryTimestamp.date(from: message.createdAt)?.formatted(date: .abbreviated, time: .shortened)
            ?? L("Unknown"))
            .font(.caption).foregroundStyle(.secondary)
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
