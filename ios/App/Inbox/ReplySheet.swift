// Sheet for answering a decision with a listed option or a free-text reply.
// Exports: ReplySheet presented from a pending card's Reply swipe.
// Dependencies: SwiftUI, HibossKit, UIKit (haptics).

import HibossKit
import SwiftUI
import UIKit

struct ReplySheet: View {
    let message: HistoryMessage
    /// Performs the reply and reports the real outcome, so the sheet stays up on
    /// failure / already-resolved instead of dismissing before the call resolves.
    var onSend: (String) async -> ReplyResult
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var submitting: String?
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if message.isPendingDecision, !message.options.isEmpty {
                    Section("Options") {
                        ForEach(message.options, id: \.self) { option in
                            Button { send(option) } label: {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    if submitting == option { ProgressView() }
                                }
                            }
                            .disabled(submitting != nil)
                        }
                    }
                }

                Section("Reply") {
                    TextField("Type a reply…", text: $draft, axis: .vertical)
                        .disabled(submitting != nil)
                    Button("Send") { send(draft) }
                        .disabled(submitting != nil || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let note {
                    Section {
                        Label(note, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(message.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func send(_ choice: String) {
        let text = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, submitting == nil else { return }
        submitting = text
        note = nil
        Task {
            let result = await onSend(text)
            submitting = nil
            switch result {
            case .sent:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            case .alreadyResolved:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                note = "Already answered elsewhere."
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                note = "Couldn't send your reply. Try again."
            }
        }
    }
}
