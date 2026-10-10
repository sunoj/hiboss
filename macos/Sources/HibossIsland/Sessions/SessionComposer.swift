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

    mutating func retarget(to message: HistoryMessage, drafts: inout [MessageID: String]) {
        let text = pinnedID.flatMap { drafts.removeValue(forKey: $0) } ?? ""
        drafts[message.id] = text
        edit(text, for: message)
    }

    mutating func discard(drafts: inout [MessageID: String]) {
        if let pinnedID { drafts.removeValue(forKey: pinnedID) }
        pinnedID = nil
    }
}

struct SessionComposer: View {
    let context: SessionContext
    @ObservedObject var reply: AttentionReplyState
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    @State private var target = SessionReplyTarget()

    private var message: HistoryMessage? { target.message(in: context) }
    private var draftID: MessageID? { target.pinnedID ?? message?.id }

    private var draft: Binding<String> {
        Binding(get: { draftID.flatMap { reply.drafts[$0] } ?? "" }, set: { text in
            if let message {
                target.edit(text, for: message)
                reply.drafts[message.id] = text
            }
        })
    }

    private var isSubmitting: Bool { draftID.map { reply.submitting.contains($0) } ?? false }

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
                unavailableTarget
            }
            if let newer = target.newerMessage(in: context) {
                Button(L("Reply to the newer message")) {
                    target.retarget(to: newer, drafts: &reply.drafts)
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

    private var unavailableTarget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unavailableTargetLabel).font(.caption).foregroundStyle(TodayStyle.secondary)
            TextField(L("Reply to session…"), text: draft, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3).disabled(true)
                .accessibilityIdentifier("session.reply")
            if target.pinnedID != nil {
                Button(L("Discard")) { target.discard(drafts: &reply.drafts) }
                    .disabled(isSubmitting).accessibilityIdentifier("session.discard")
            }
        }
    }

    private var unavailableTargetLabel: String {
        if !context.snapshot.answerability.isLoaded { return L("Checking…") }
        if target.pinnedID != nil {
            return L("This draft's target is unavailable. Discard it or reply to a newer message.")
        }
        return L("No eligible agent message to reply to in this session.")
    }

    private func editor(for message: HistoryMessage) -> some View {
        HStack(alignment: .bottom) {
            TextField(L("Reply to session…"), text: draft, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...3).disabled(isSubmitting)
                .accessibilityIdentifier("session.reply")
            if isSubmitting { ProgressView().controlSize(.small) }
            Button(L("Send reply")) {
                guard context.snapshot.answerability.permitsReply(to: message) else { return }
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
