// Persistent native session reply field targeting the newest agent message.
// Exports: SessionComposer; shares message drafts and retry feedback with History.
// Dependencies: SwiftUI, HibossKit, and AttentionReplyState.

import HibossKit
import SwiftUI

struct SessionComposer: View {
    let message: HistoryMessage?
    @ObservedObject var reply: AttentionReplyState
    let onChoose: (String, MessageID) async -> ReplyFeedback?

    private var draft: Binding<String> {
        Binding(get: { message.flatMap { reply.drafts[$0.id] } ?? "" }, set: { text in
            if let message { reply.drafts[message.id] = text }
        })
    }

    private var isSubmitting: Bool { message.map { reply.submitting.contains($0.id) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message {
                Text(L("Reply to \(message.historyDisplayName)")).font(.caption)
                    .foregroundStyle(TodayStyle.secondary)
                HStack(alignment: .bottom) {
                    TextField(L("Reply to session…"), text: draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3).disabled(isSubmitting)
                        .accessibilityIdentifier("session.reply")
                    if isSubmitting { ProgressView().controlSize(.small) }
                    Button(L("Send reply")) {
                        let text = draft.wrappedValue
                        Task { await reply.send(text, for: message.id, using: onChoose) }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSubmitting || draft.wrappedValue
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("session.send")
                }
                if let error = reply.errors[message.id] {
                    Text(error.text).font(.callout).foregroundStyle(TodayStyle.signal)
                }
            } else {
                TextField(L("Reply to session…"), text: .constant(""))
                    .textFieldStyle(.roundedBorder).disabled(true)
                Text(L("A reply needs an agent message in this session."))
                    .font(.caption).foregroundStyle(TodayStyle.secondary)
            }
        }
        .padding(12).background(TodayStyle.surface)
        .accessibilityIdentifier("session.composer")
    }
}
