// Session thread: header and the session's messages in one plain scroll surface like Today.
// Exports: SessionThreadView; no search, filter, title or toolbar items of its own.
// Dependencies: SwiftUI, HibossKit, SessionHeader, HistoryThreadRow, and SessionContext.

import HibossKit
import SwiftUI

struct SessionThreadView: View {
    let context: SessionContext
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var reply: AttentionReplyState
    let connection: ConnectionState
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    @State private var expandedMessages: Set<MessageID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let threads = HistoryMessageLogic.scopedThreads(snapshot: context.snapshot, scope: .session(context.id))
        let presentation = SessionThreadLogic(threads: threads,
            answerability: context.snapshot.answerability, now: context.snapshot.now)
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SessionHeader(context: context, connection: connection)
                    rows(threads: threads, presentation: presentation, reader: reader)
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .id(context.id)
            .accessibilityIdentifier("session.thread")
        }
    }

    @ViewBuilder
    private func rows(threads: [MessageThread], presentation: SessionThreadLogic,
                      reader: ScrollViewProxy) -> some View {
        if threads.isEmpty, flow.historyState == .loading, flow.historyLoadedAt == nil {
            ProgressView(L("Loading messages…")).padding(24).frame(maxWidth: .infinity)
        } else if threads.isEmpty {
            ContentUnavailableView(L("No Messages"), systemImage: "tray",
                description: Text(L("Agent messages will appear here.")))
                .padding(.vertical, 24)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !presentation.needsYou.isEmpty {
                    Text(L("Needs you")).font(.headline).padding(.top, 10)
                    ForEach(presentation.needsYou) { thread in
                        row(thread, pinned: true, reader: reader)
                        Divider()
                    }
                }
                Text(L("Conversation")).font(.headline).padding(.top, 10).padding(.bottom, 8)
                conversation(presentation: presentation, reader: reader)
            }
        }
    }

    @ViewBuilder
    private func conversation(presentation: SessionThreadLogic, reader: ScrollViewProxy) -> some View {
        ForEach(presentation.days()) { day in
            Text(SessionThreadLogic.dayTitle(day.id, now: context.snapshot.now))
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 12)
            ForEach(day.cards) { card in
                if let root = card.threads.first {
                    row(root, merged: card.threads.dropFirst().map(\.message), reader: reader)
                    Divider()
                }
            }
        }
    }

    /// A pinned row and its Conversation row are different views: when a decision is answered
    /// it moves between the sections, and a shared identity kept the pinned card on screen.
    private func row(_ thread: MessageThread, merged: [HistoryMessage] = [], pinned: Bool = false,
                     reader: ScrollViewProxy) -> some View {
        let identity = SessionRowID(thread: thread.id, pinned: pinned)
        return HistoryThreadRow(thread: thread,
            decision: context.decisions.first { $0.id == thread.id }, usesV4: true,
            sessionEntries: true, mergedMessages: merged,
            answerability: SessionThreadLogic.answerability(
                for: thread, from: context.snapshot.answerability),
            reply: reply, isExpanded: Binding(
                get: { expandedMessages.contains(thread.id) },
                set: { expanded in
                    if expanded { expandedMessages.insert(thread.id) }
                    else { expandedMessages.remove(thread.id) }
                }), isSearching: false,
            onCollapse: {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    reader.scrollTo(identity, anchor: .top)
                }
            }, onChoose: { choice in await onChoose(choice, thread.id) })
            .id(identity)
    }
}

/// Scroll and view identity of one session row, distinct per section.
struct SessionRowID: Hashable {
    let thread: MessageID
    let pinned: Bool
}
