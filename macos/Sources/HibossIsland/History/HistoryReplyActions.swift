// In-message choices and a focused reply composer with shared drafts and retry state.
// Exports: HistoryReplyActions; media and errors stay inside the message stream.
// Dependencies: SwiftUI, HibossKit, AttentionReplyState.

import HibossKit
import SwiftUI

struct HistoryReplyActions: View {
    let message: HistoryMessage
    @ObservedObject var reply: AttentionReplyState
    let canAnswer: Bool
    let onChoose: (String) async -> ReplyFeedback?
    @State private var showsComposer = false
    @FocusState private var editorFocused: Bool

    private var isSubmitting: Bool { reply.submitting.contains(message.id) }
    private var hasDraft: Bool { !(reply.drafts[message.id] ?? "").isEmpty }
    private var draft: Binding<String> {
        Binding(get: { reply.drafts[message.id] ?? "" }, set: { reply.drafts[message.id] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canAnswer {
                choices
                if let feedback = reply.errors[message.id] {
                    Label(hasDraft ? feedback.text : feedback.choiceText, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsComposer || hasDraft {
                    composer
                } else {
                    Button(L("Write a reply"), systemImage: "arrowshape.turn.up.left") {
                        showsComposer = true
                        editorFocused = true
                    }
                    .buttonStyle(.borderless).disabled(isSubmitting)
                }
                if isSubmitting { ProgressView(L("Sending…")).controlSize(.small) }
            } else {
                Label(L("Replies closed"), systemImage: "checkmark.bubble")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(L("Choices")) { choices }
                    .font(.callout)
            }
        }
        .accessibilityIdentifier("history.actions.\(message.id.rawValue)")
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(message.options.enumerated()), id: \.offset) { _, option in
                if let media = message.metadata?.optionMedia.first(where: { $0.label == option }) {
                    inlineMedia(media)
                }
                choice(option)
            }
        }
    }

    @ViewBuilder
    private func choice(_ option: String) -> some View {
        if canAnswer {
            Button { send(option) } label: {
                HStack(alignment: .top, spacing: 6) {
                    Text(option).fixedSize(horizontal: false, vertical: true)
                    if option == message.defaultOption {
                        Text(L("default")).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered).disabled(isSubmitting)
        } else {
            Text(option).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Reply with your own instruction…"), text: draft, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5)
                .focused($editorFocused).disabled(isSubmitting)
                .accessibilityIdentifier("history.reply.\(message.id.rawValue)")
            if editorFocused {
                sendButton.keyboardShortcut(.return, modifiers: .command)
            } else {
                sendButton
            }
        }
    }

    private var sendButton: some View {
        Button(L("Send reply")) { send(draft.wrappedValue) }
            .disabled(isSubmitting || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("history.send.\(message.id.rawValue)")
    }

    private func inlineMedia(_ media: OptionMedia) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: URL(string: media.url)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                case .failure: Label(L("Image unavailable"), systemImage: "photo.badge.exclamationmark")
                case .empty: ProgressView()
                @unknown default: EmptyView()
                }
            }
            .frame(maxHeight: 280).accessibilityLabel(media.label)
            if let caption = media.caption { Text(caption).font(.caption).textSelection(.enabled) }
        }
    }

    private func send(_ text: String) {
        guard canAnswer, message.canAnswerHistory(at: .now) else { return }
        Task { await reply.send(text, for: message.id) { choice, _ in await onChoose(choice) } }
    }
}
