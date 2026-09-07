// Native attention composer and message-scoped drafts that survive selection and resizing.
// Exports: AttentionReplyState and AttentionReplyComposer.
// Dependencies: SwiftUI, HibossKit MessageID, asynchronous reply callback.

import HibossKit
import SwiftUI

@MainActor
final class AttentionReplyState: ObservableObject {
    @Published var drafts: [MessageID: String] = [:]
    @Published private(set) var submitting: Set<MessageID> = []
    @Published private(set) var errors: [MessageID: String] = [:]

    func send(
        _ text: String,
        for id: MessageID,
        using submit: (String, MessageID) async -> Bool
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !submitting.contains(id) else { return }
        submitting.insert(id)
        errors[id] = nil
        let succeeded = await submit(trimmed, id)
        submitting.remove(id)
        if succeeded {
            drafts[id] = nil
        } else {
            errors[id] = L("Reply failed. Your draft is saved. Try again.")
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
