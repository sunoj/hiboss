// Native attention composer and message-scoped drafts that survive selection and resizing.
// Exports: AttentionReplyState, AttentionReplyComposer, OptionFlowStore.answer, ReplyFeedback copy.
// Dependencies: SwiftUI, HibossKit OptionFlowStore and ReplyFeedback.

import Combine
import HibossKit
import SwiftUI

@MainActor
final class AttentionReplyState: ObservableObject {
    @Published var drafts: [MessageID: String] = [:]
    @Published private(set) var submitting: Set<MessageID> = []
    @Published private(set) var errors: [MessageID: ReplyFeedback] = [:]
    private let identity: AccountAuthorization

    init(identity: AccountAuthorization = .shared) {
        self.identity = identity
        authorizationObservation = identity.observe { [weak self] _ in self?.reset() }
    }

    func reset() {
        drafts.removeAll()
        submitting.removeAll()
        errors.removeAll()
    }

    private var authorizationObservation: AnyCancellable?
    /// `submit` returns nil when the server accepted the reply; otherwise the draft stays and
    /// the message-specific feedback is shown for `id` only.
    func send(
        _ text: String,
        for id: MessageID,
        using submit: (String, MessageID) async -> ReplyFeedback?
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !submitting.contains(id) else { return }
        let generation = identity.generation
        submitting.insert(id)
        errors[id] = nil
        let feedback = await submit(trimmed, id)
        guard generation == identity.generation else { return }
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
    /// The live question goes through `submit`, so an accepted answer dismisses it as this device's;
    /// a form answer (`answers`) always goes through the history path, which carries it.
    func answer(_ text: String, for id: MessageID) async -> ReplyFeedback? {
        await answer(text, answers: nil, for: id)
    }

    func answer(_ text: String, answers: PanelValue?, for id: MessageID) async -> ReplyFeedback? {
        let accepted = activeMessage?.id == id && answers == nil
            ? await submit(text, for: id)
            : await answerHistory(text, answers: answers, for: id)
        if accepted { return nil }
        return replyFeedback[id] ?? .failed("")
    }
}

extension ReplyFeedback {
    /// Copy under a composer: a closed decision is final and names no actor or answer;
    /// a failure keeps the draft.
    var text: String {
        switch self {
        case .alreadyResolved: L("No longer open")
        case .failed: L("Reply failed. Your draft is saved. Try again.")
        }
    }

    /// Copy for a one-click choice, which has no draft to keep.
    var choiceText: String {
        switch self {
        case .alreadyResolved: L("No longer open")
        case .failed: L("Couldn't send your reply. Try again.")
        }
    }
}

struct AttentionReplyComposer: View {
    @Binding var text: String
    /// Names the question a free-text answer goes to, so it is not read as a new instruction.
    var question: String?
    let isSubmitting: Bool
    let error: String?
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question {
                Text(L("Custom answer to: \(question)")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
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
