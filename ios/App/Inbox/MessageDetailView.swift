// Decision-first detail for a single message: question, shared timing and choices, then details.
// Exports: MessageDetailView.
// Dependencies: SwiftUI, HibossKit, DecisionOptions, DecisionTiming, MessageDetailsCard.

import HibossKit
import SwiftUI
import UIKit

struct MessageDetailView: View {
    @ObservedObject var store: InboxStore
    let messageID: MessageID
    @State private var replyDraft = ""
    @State private var actionNote: String?
    @State private var fallback: Fallback = .loading
    @State private var loadAttempt = 0
    @Environment(\.dismiss) private var dismiss

    /// What to show when the message isn't (yet) in history.
    private enum Fallback { case loading, missing, failed(String) }

    private var message: HistoryMessage? { store.message(for: messageID) }

    /// The reply in flight for this decision from any surface (Home, transcript, a notification).
    private var submitting: String? { store.replying[messageID] }

    /// The boss reply that resolved this decision, if it's in the loaded history.
    private var reply: HistoryMessage? {
        store.reply(to: messageID)
    }

    /// The chosen option text, trimmed and non-empty, or nil if unresolved.
    private var chosenAnswer: String? {
        guard let body = reply?.body.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else { return nil }
        return body
    }

    /// Whether an option is the chosen one. The server trims the stored answer
    /// while options keep the agent's raw text, so compare trim-normalized to
    /// avoid a whitespace mismatch that would both un-mark it and duplicate it
    /// as a "Custom reply" row.
    private func isChosen(_ option: String) -> Bool {
        option.trimmingCharacters(in: .whitespacesAndNewlines) == chosenAnswer
    }

    /// The recorded answer and its source, so a timeout default is never shown as a choice.
    private var settlement: DecisionSettlement? {
        reply.flatMap(DecisionSettlement.init(reply:))
    }

    var body: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    question(for: message)
                    if let actionNote {
                        Label(actionNote, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warn)
                            .font(.hbCallout)
                    }
                    decisionSection(for: message)
                    MessageDetailsCard(message: message)
                    if let session = sessionRoute(for: message) {
                        NavigationLink(value: session) {
                            Label("View session · \(session.label)", systemImage: "square.stack.3d.up")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.paper)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(verbatim: title(for: message)))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            fallbackView
        }
    }

    /// The question leads, plain and large; it wraps fully at every text size.
    private func question(for message: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: message.body)
                .font(.hbLargeTitle)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("message-question")
            if let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty, content != message.body.trimmingCharacters(in: .whitespacesAndNewlines) {
                Text(verbatim: content)
                    .font(.hbCallout)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    /// Session, then project, then agent: where the question came from, not who typed it.
    private func title(for message: HistoryMessage) -> String {
        let session = message.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let project = message.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !session.isEmpty ? session : (!project.isEmpty ? project : message.displayName)
    }

    /// Shown while the message hasn't landed in history. Holds a spinner until the
    /// store is connected and a clean refresh has run — a live-stream arrival or a
    /// successful fetch re-renders into the message branch above. Only a genuinely
    /// absent message (after a clean load) or exhausted retries shows "not found".
    @ViewBuilder private var fallbackView: some View {
        switch fallback {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Loading…")
                .navigationBarTitleDisplayMode(.inline)
                .task(id: loadAttempt) { await load() }
        case .missing:
            unavailableView(
                title: String(localized: "Message not found"),
                icon: "questionmark.circle",
                description: String(localized: "It may have been cleared or expired.")
            )
        case .failed(let reason):
            unavailableView(
                title: String(localized: "Couldn't load message"),
                icon: "wifi.exclamationmark",
                description: reason
            )
        }
    }

    private func unavailableView(title: String, icon: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(verbatim: description)
        } actions: {
            Button("Retry") { fallback = .loading; loadAttempt += 1 }
        }
    }

    /// Waits briefly for restored credentials, then fetches only the notification
    /// target. Full history may continue loading independently in the background.
    private func load() async {
        if message != nil { return }
        for _ in 0..<AppConstants.API.notificationReadinessChecks where !store.isReady {
            try? await Task.sleep(for: AppConstants.API.notificationReadinessDelay)
            if Task.isCancelled { return }
        }
        guard store.isReady else {
            fallback = .failed(String(localized: "Connection isn't ready."))
            return
        }
        let result = await store.loadMessage(messageID)
        guard !Task.isCancelled else { return }
        switch result {
        case .loaded:
            break
        case .missing:
            fallback = .missing
        case .failed(let reason):
            fallback = .failed(reason)
        }
    }

    /// Pending: shared timing, choices, and a free-text reply. Resolved: a read-only
    /// picked/others list, with the chosen option checked and its source noted.
    @ViewBuilder private func decisionSection(for message: HistoryMessage) -> some View {
        if message.isPendingDecision || AttentionModel.needsTextReply(message) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let timing = DecisionTiming(message: message, now: context.date)
                pendingDecision(for: message, timing: timing)
            }
        } else if message.isDecision {
            resolvedDecision(for: message)
        }
    }

    private func pendingDecision(for message: HistoryMessage, timing: DecisionTiming) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DecisionTimingView(timing: timing, messageID: message.id)
            OptionMediaComparison(
                options: message.options,
                media: message.metadata?.optionMedia ?? []
            )
            if !message.options.isEmpty {
                DecisionOptions(options: message.options, timing: timing, submitting: submitting) {
                    submit($0, for: message.id)
                }
            }
            replyField(for: message)
        }
    }

    private func resolvedDecision(for message: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Options").hbLabel().foregroundStyle(Theme.ink2)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(message.options, id: \.self) { option in
                    optionRow(option, chosen: isChosen(option))
                }
                if let answer = chosenAnswer, !message.options.contains(where: isChosen) {
                    optionRow(answer, chosen: true, custom: true)
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            decisionFooter(for: message)?.font(.hbFootnote).foregroundStyle(Theme.ink2)
        }
    }

    private func replyField(for message: HistoryMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Reply…", text: $replyDraft, axis: .vertical)
                .accessibilityIdentifier("message-reply-draft")
                .disabled(submitting != nil)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button { submit(replyDraft, for: message.id) } label: {
                Text("Send").frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(submitting != nil || replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private func optionRow(_ text: String, chosen: Bool, custom: Bool = false) -> some View {
        let automatic = chosen && settlement?.isAutoDefault == true
        HStack(spacing: 12) {
            Image(systemName: chosen ? (settlement?.symbol ?? "checkmark.circle.fill") : "circle")
                .foregroundStyle(chosen ? Theme.accent : Theme.ink2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text).foregroundStyle(chosen ? Theme.ink : Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if custom { Text("Custom reply").font(.caption2).foregroundStyle(Theme.ink2) }
            }
            Spacer()
            if chosen { (automatic ? Text("Auto-selected") : Text("Selected")).font(.caption).foregroundStyle(Theme.ink2) }
        }
    }

    private func decisionFooter(for message: HistoryMessage) -> Text? {
        if let settlement { return settlement.attribution }
        let expired = message.status == "expired"
            || (message.expirationDate.map { $0 <= Date() } ?? false)
        if expired {
            if let def = message.defaultOption { return Text("Timed out — default: \(def)") }
            return Text("Expired — no response")
        }
        return nil
    }

    private func submit(_ choice: String, for id: MessageID) {
        let text = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, store.replying[id] == nil else { return }
        actionNote = nil
        Task {
            switch await store.reply(text, to: id) {
            case .busy:
                break
            case .sent:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            case .alreadyResolved:
                // Don't claim success: refresh re-renders into the resolved branch
                // showing the answer that actually won.
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                actionNote = String(localized: "Already answered elsewhere — showing the recorded outcome.")
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                actionNote = store.loadError ?? String(localized: "Couldn't send your reply. Try again.")
            }
        }
    }

    private func sessionRoute(for message: HistoryMessage) -> SessionRoute? {
        guard let id = message.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        let label = message.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionRoute(id: id, label: label?.isEmpty == false ? label! : String(id.prefix(8)))
    }

}
