// Hosts attention and history message surfaces within the main workspace.
// Exports: MainMessageSurface; navigation and persistent state belong to MainView.
// Dependencies: SwiftUI, HibossKit, and shared attention reply state.

import SwiftUI
import HibossKit

struct MainMessageSurface: View {
    let snapshot: OverviewSnapshot
    let destination: OverviewDestination
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var reply: AttentionReplyState
    let isPreview: Bool
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    let onSettings: () -> Void

    var body: some View {
        if snapshot.history.isEmpty, flow.connectionState == .disconnected, !isPreview {
            ContentUnavailableView {
                Label(L("Connect to HiBoss"), systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(L("Connect to receive agent messages."))
            } actions: {
                Button(L("Settings"), action: onSettings)
            }
        } else if case let .category(category) = destination, category.isAttention {
            AttentionView(flow: flow, reply: reply, category: category,
                items: snapshot.attention(for: category),
                now: snapshot.now, answerability: snapshot.answerability, onChoose: onChoose)
        } else {
            HistoryView(flow: flow, snapshot: snapshot, scope: destination, onChoose: onChoose, reply: reply)
        }
    }
}
