// Compact chronological thread members and neutral emoji reaction summaries.
// Exports: SessionThreadEntries and SessionReactionChips for session cards.
// Dependencies: SwiftUI, HibossKit, and the shared history reading/settlement views.

import HibossKit
import SwiftUI

struct SessionReactionChips: View {
    let message: HistoryMessage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(SessionThreadLogic.reactionChips(message), id: \.emoji) { chip in
            Text(chip.text).font(.caption)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .accessibilityLabel(chip.accessibilityLabel)
        }
    }
}

struct SessionThreadEntries: View {
    let thread: MessageThread
    var merged: [HistoryMessage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(thread.entries + merged) { entry in
                member(entry)
            }
        }
        .padding(.leading, 12)
    }

    private func member(_ entry: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                if entry.isBossHistoryMessage {
                    Text(L("Me")).font(.caption.weight(.semibold))
                } else if entry.agentName != thread.message.agentName {
                    Text(entry.historyDisplayName).font(.caption.weight(.semibold))
                }
                TimelineView(.periodic(from: .now, by: 60)) { tick in
                    Text(ISODate.parse(entry.createdAt).map { SharedTimestamp.string($0, now: tick.date) }
                        ?? L("Unknown"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if entry.isBossHistoryMessage, !thread.message.options.isEmpty {
                let answered = MessageThread(message: thread.message, replies: [entry])
                ResolvedBanner(thread: answered, outcome: answered.outcome)
                if entry.content != nil || entry.metadata?.attachment != nil {
                    HistoryMessageBody(content: HistoryReadingContent(body: "", content: entry.content,
                        attachment: entry.metadata?.attachment), isSearching: false,
                        isExpanded: .constant(true), onCollapse: {})
                }
            } else {
                HistoryMessageBody(content: HistoryReadingContent(message: entry), isSearching: false,
                    isExpanded: .constant(true), onCollapse: {})
            }
            SessionReactionChips(message: entry)
            if SessionThreadLogic.hasDetails(entry) {
                DisclosureGroup(L("Details")) {
                    ForEach(entry.metadata?.files ?? [], id: \.self) { Text($0).textSelection(.enabled) }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("session.entry.\(entry.id.rawValue)")
    }
}
