// Decision inspector preserving message-scoped replies while the dashboard stays visible.
// Exports: DashboardDecisionDetail with native choices and free-form replies.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, and shared attention components.

import HibossKit
import SwiftUI

struct DashboardDecisionDetail: View {
    let item: AttentionItem
    let now: Date
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var reply: AttentionReplyState
    let isPreview: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Decision")).font(.headline)
                Spacer()
                Button(action: onClose) { Label(L("Close"), systemImage: "xmark") }
                    .labelStyle(.iconOnly)
            }
            .padding()
            Divider()
            AttentionDetail(item: item, now: now, onChoose: send)
                .disabled(isPreview || reply.submitting.contains(item.id))
            if isPreview {
                Text(L("Sample decisions · Local preview"))
                    .font(.callout).foregroundStyle(.secondary).padding()
            } else {
                AttentionReplyComposer(text: Binding(
                    get: { reply.drafts[item.id] ?? "" }, set: { reply.drafts[item.id] = $0 }
                ), isSubmitting: reply.submitting.contains(item.id), error: reply.errors[item.id],
                    onSend: { send(reply.drafts[item.id] ?? "") })
            }
        }
        .accessibilityIdentifier("dashboard.decisionDetail")
    }

    private func send(_ text: String) {
        guard !isPreview else { return }
        Task { await reply.send(text, for: item.id) { choice, id in
            await flow.answerHistory(choice, for: id)
        } }
    }
}
