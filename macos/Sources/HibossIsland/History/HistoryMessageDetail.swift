// Notification window wrapper around the shared History thread row.
// Exports: HistoryMessageDetail; shared drafts and expansion stay in the row.
// Dependencies: SwiftUI, HibossKit, HistoryThreadRow, and AttentionReplyState.

import HibossKit
import SwiftUI

struct HistoryMessageDetail: View {
    let message: HistoryMessage
    @ObservedObject var reply: AttentionReplyState
    let onChoose: (String) async -> ReplyFeedback?
    @Environment(\.dismiss) private var dismiss
    var replies: [HistoryMessage] = []
    @State private var isExpanded = true

    var body: some View {
        ScrollView {
            HistoryThreadRow(thread: MessageThread(message: message, replies: replies), reply: reply,
                isExpanded: $isExpanded, isSearching: false, onCollapse: {}, onChoose: { text in
                    let feedback = await onChoose(text)
                    if feedback == nil { dismiss() }
                    return feedback
                })
                .padding(.horizontal, 20)
        }
        .defaultScrollAnchor((reply.drafts[message.id] ?? "").isEmpty ? .top : .bottom)
        .frame(minWidth: 360, idealWidth: 520, minHeight: 320, idealHeight: 520)
        .navigationTitle(L("Message details"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Close")) { dismiss() }
            }
        }
    }
}
