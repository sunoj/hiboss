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

    private var threads: [MessageThread] {
        HistoryMessageLogic.scopedThreads(snapshot: context.snapshot, scope: .session(context.id))
    }

    private var presentation: SessionThreadLogic {
        SessionThreadLogic(threads: threads, answerability: context.snapshot.answerability,
            now: context.snapshot.now)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SessionHeader(context: context, connection: connection)
                    Divider()
                    rows(reader: reader)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(context.id)
            .accessibilityIdentifier("session.thread")
        }
    }

    @ViewBuilder
    private func rows(reader: ScrollViewProxy) -> some View {
        if threads.isEmpty, flow.historyState == .loading, flow.historyLoadedAt == nil {
            ProgressView(L("Loading messages…")).padding(24).frame(maxWidth: .infinity)
        } else if threads.isEmpty {
            ContentUnavailableView(L("No Messages"), systemImage: "tray",
                description: Text(L("Agent messages will appear here.")))
                .padding(.vertical, 24)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !presentation.needsYou.isEmpty {
                    Text(L("Needs you")).font(.headline).padding(.top, 20)
                    ForEach(presentation.needsYou) { thread in
                        row(thread, reader: reader)
                        Divider()
                    }
                }
                Text(L("Conversation")).font(.headline).padding(.vertical, 20)
                conversation(reader: reader)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func conversation(reader: ScrollViewProxy) -> some View {
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

    private func row(_ thread: MessageThread, merged: [HistoryMessage] = [],
                     reader: ScrollViewProxy) -> some View {
        HistoryThreadRow(thread: thread,
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
                    reader.scrollTo(thread.id, anchor: .top)
                }
            }, onChoose: { choice in await onChoose(choice, thread.id) })
            .id(thread.id)
    }
}
