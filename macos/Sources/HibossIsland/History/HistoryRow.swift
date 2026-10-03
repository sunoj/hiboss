// Inline session message with readable text, in-place replies, and optional metadata.
// Exports: HistoryRow; message text never opens a sheet or consumes double-clicks.
// Dependencies: SwiftUI, HibossKit, HistoryMessageBody, HistoryReplyActions.

import HibossKit
import SwiftUI

struct HistoryRow: View {
    let message: HistoryMessage
    @ObservedObject var reply: AttentionReplyState
    @Binding var isExpanded: Bool
    let isSearching: Bool
    let onCollapse: () -> Void
    let onChoose: (String) async -> ReplyFeedback?
    @State private var now = Date()

    private var content: HistoryReadingContent {
        HistoryReadingContent(body: message.body, content: message.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 12) {
                header
                HistoryMessageBody(content: content, isSearching: isSearching,
                    isExpanded: $isExpanded, onCollapse: onCollapse)
                if let outcome = message.historyAutoDecidedLabel {
                    Label(outcome, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                if !message.options.isEmpty {
                    HistoryReplyActions(message: message, reply: reply,
                        canAnswer: message.canAnswerHistory(at: now), onChoose: onChoose)
                }
                metadata
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.message.\(message.id.rawValue)")
        .task(id: message.expiresAt) { await observeDeadline() }
    }

    private var avatar: some View {
        Text(message.historyMonogram).font(.callout.weight(.semibold))
            .foregroundStyle(message.isBossHistoryMessage ? Color.accentColor : .secondary)
            .frame(width: 34, height: 34)
            .background(message.isBossHistoryMessage ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05),
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
        DisclosureGroup(L("Details")) {
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
