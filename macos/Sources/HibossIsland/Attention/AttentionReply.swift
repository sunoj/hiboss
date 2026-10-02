// Native attention composer and message-scoped drafts that survive selection and resizing.
// Exports: AttentionReplyState, AttentionReplyComposer, OptionFlowStore.answer, ReplyFeedback copy.
// Dependencies: SwiftUI, HibossKit OptionFlowStore and ReplyFeedback.

import HibossKit
import SwiftUI

@MainActor
final class AttentionReplyState: ObservableObject {
    @Published var drafts: [MessageID: String] = [:]
    @Published private(set) var submitting: Set<MessageID> = []
    @Published private(set) var errors: [MessageID: ReplyFeedback] = [:]

    /// `submit` returns nil when the server accepted the reply; otherwise the draft stays and
    /// the message-specific feedback is shown for `id` only.
    func send(
        _ text: String,
        for id: MessageID,
        using submit: (String, MessageID) async -> ReplyFeedback?
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !submitting.contains(id) else { return }
        submitting.insert(id)
        errors[id] = nil
        let feedback = await submit(trimmed, id)
        submitting.remove(id)
        if let feedback {
            errors[id] = feedback
        } else {
            drafts[id] = nil
        }
    }
}

extension OptionFlowStore {
    /// Answers any message by id and reports that message's own feedback; nil means accepted.
    func answer(_ text: String, for id: MessageID) async -> ReplyFeedback? {
        if await answerHistory(text, for: id) { return nil }
        return replyFeedback[id] ?? .failed("")
    }
}

extension ReplyFeedback {
    /// Copy under a composer: an answer recorded elsewhere is final; a failure keeps the draft.
    var text: String {
        switch self {
        case .alreadyAnswered: L("That decision was already answered elsewhere.")
        case .failed: L("Reply failed. Your draft is saved. Try again.")
        }
    }

    /// Copy for a one-click choice, which has no draft to keep.
    var choiceText: String {
        switch self {
        case .alreadyAnswered: L("That decision was already answered elsewhere.")
        case .failed: L("Couldn't send your reply. Try again.")
        }
    }
}

struct AttentionReplyComposer: View {
    @Binding var text: String
    let isSubmitting: Bool
    let error: String?
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Reply with your own instruction…"), text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .accessibilityIdentifier("attention.reply")
                .disabled(isSubmitting)
            HStack {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(L("Send reply"), action: onSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isSubmitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("attention.send")
            }
        }
        .padding()
        .background(.bar)
    }
}
