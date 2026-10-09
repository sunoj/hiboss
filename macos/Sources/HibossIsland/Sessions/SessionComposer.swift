// Persistent native session reply field targeting the newest agent message.
// Exports: SessionComposer and SessionReplyTarget; shares drafts and retry feedback with History.
// Dependencies: SwiftUI, HibossKit, SessionContext, and AttentionReplyState.

import HibossKit
import SwiftUI

struct SessionReplyTarget {
    private(set) var pinnedID: MessageID?

    func message(in context: SessionContext) -> HistoryMessage? {
        guard let pinnedID else { return context.newestAgentMessage }
        return context.replyTargets.first { $0.id == pinnedID }
    }

    func newerMessage(in context: SessionContext) -> HistoryMessage? {
        guard let pinnedID, let newest = context.newestAgentMessage, newest.id != pinnedID else { return nil }
        return newest
    }

    mutating func edit(_ text: String, for message: HistoryMessage) {
        pinnedID = text.isEmpty ? nil : message.id
    }

    mutating func clearIfEmpty(drafts: [MessageID: String]) {
        if let pinnedID, drafts[pinnedID, default: ""].isEmpty { self.pinnedID = nil }
    }
}

struct SessionComposer: View {
    let context: SessionContext
    @ObservedObject var reply: AttentionReplyState
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    @State private var target = SessionReplyTarget()

    private var message: HistoryMessage? { target.message(in: context) }

    private var draft: Binding<String> {
        Binding(get: { message.flatMap { reply.drafts[$0.id] } ?? "" }, set: { text in
            if let message {
                target.edit(text, for: message)
                reply.drafts[message.id] = text
            }
        })
    }

    private var isSubmitting: Bool { message.map { reply.submitting.contains($0.id) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message {
                Text(context.replyTargetLabel(for: message)).font(.caption)
                    .foregroundStyle(TodayStyle.secondary)
                    .accessibilityIdentifier("session.replyTarget")
                editor(for: message)
                if let error = reply.errors[message.id] {
                    Text(error.text).font(.callout).foregroundStyle(TodayStyle.signal)
                }
            } else {
                Text(L("No eligible agent message to reply to in this session."))
                    .font(.caption).foregroundStyle(TodayStyle.secondary)
                TextField(L("Reply to session…"), text: .constant(""))
                    .textFieldStyle(.roundedBorder).disabled(true)
            }
            if let newer = target.newerMessage(in: context) {
                Button(L("Reply to the newer message")) {
                    target.edit(reply.drafts[newer.id, default: ""], for: newer)
                }
                .disabled(isSubmitting)
                .accessibilityIdentifier("session.replyNewer")
            }
        }
        .padding(12).background(TodayStyle.surface)
        .accessibilityIdentifier("session.composer")
        .onAppear {
            if let message { target.edit(reply.drafts[message.id, default: ""], for: message) }
        }
        .onChange(of: reply.drafts) { target.clearIfEmpty(drafts: reply.drafts) }
    }

    private func editor(for message: HistoryMessage) -> some View {
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
    }
}
