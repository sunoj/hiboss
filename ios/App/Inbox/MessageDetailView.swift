// Decision-first detail for a single message: question, shared timing and choices, then details.
// Exports: MessageDetailView.
// Dependencies: SwiftUI, HibossKit, DecisionOptions, DecisionTiming, MessageDetailsCard.

import HibossKit
import SwiftUI
import UIKit

struct MessageDetailView: View {
    @ObservedObject var store: InboxStore
    let messageID: MessageID
    var onOpenSession: ((SessionRoute) -> Void)? = nil
    @StateObject private var facts = SessionFactsStore()
    private var replyDraft: String {
        get { store.messageDrafts[messageID] ?? "" }
        nonmutating set { store.messageDrafts[messageID] = newValue }
    }
    private var draftBinding: Binding<String> {
        Binding(get: { replyDraft }, set: { replyDraft = $0 })
    }
    @State private var actionNote: String?
    @State var fallback: Fallback = .loading
    @State var loadAttempt = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openConnectionSettings) private var openSettings

    /// What to show when the message isn't (yet) in history.
    enum Fallback { case loading, missing, failed(String) }

    private var message: HistoryMessage? { store.message(for: messageID) }

    /// The reply in flight for this decision from any surface (Home, transcript, a notification).
    private var submitting: String? { store.replying[messageID] }

    /// The boss reply that resolved this decision, if it's in the loaded history.
    private var reply: HistoryMessage? {
        store.reply(to: messageID)
    }

    /// The recorded answer and its source, so a timeout default is never shown as a choice.
    private var settlement: DecisionSettlement? {
        store.settlement(for: messageID) ?? reply.flatMap(DecisionSettlement.init(reply:))
    }

    var body: some View {
        if let message {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {
                    DecisionProvenance(message: message, session: facts.session)
                    question(for: message)
                    DecisionContextCard(message: message)
                    if !(message.metadata?.reactionGroups.isEmpty ?? true) {
                        MessageReactions(message: message)
                    }
                    if let actionNote {
                        Label(actionNote, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warn)
                            .font(.hbCallout)
                    }
                    decisionSection(for: message)
                    sessionLink(for: message)
                    MessageDetailsCard(message: message)
                }
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
            }
            .hbReadableWidth()
            .accessibilityIdentifier("decision-detail")
            .background(Theme.paper)
            .onChange(of: message, initial: true) { _, current in
                store.retainOpenMessage(current)
            }
            .task(id: message.sessionId) {
                if let id = message.sessionId {
                    await facts.load(id: id, api: store.api as? any SessionsServing)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(verbatim: title(for: message)))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            fallbackView
        }
    }

    @ViewBuilder private func sessionLink(for message: HistoryMessage) -> some View {
        if let session = sessionRoute(for: message) {
            if let onOpenSession {
                Button { onOpenSession(session) } label: {
                    Label("Open session", systemImage: "text.alignleft")
                }.hbButton(.secondary)
            } else {
                NavigationLink(value: session) {
                    Label("Open session", systemImage: "text.alignleft")
                }.hbButton(.secondary)
            }
        }
    }

    /// The question leads, plain and large; it wraps fully at every text size.
    private func question(for message: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(verbatim: message.messageText.title)
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("message-question")
            if message.direction == "agent_to_boss", let attachment = message.metadata?.attachment {
                MessageAttachmentView(attachment: attachment)
            }
        }
    }

    /// Session, then project, then agent: where the question came from, not who typed it.
    private func title(for message: HistoryMessage) -> String {
        let session = message.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let project = message.project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !session.isEmpty ? session : (!project.isEmpty ? project : message.displayName)
    }

    /// Pending: shared timing, choices, and a free-text reply. Resolved: a read-only
    /// picked/others list, with the chosen option checked and its source noted.
    @ViewBuilder private func decisionSection(for message: HistoryMessage) -> some View {
        if message.isDecision,
           store.answerability(for: message.id) == .checking {
            Button("Checking…") {}.hbButton(.secondary).disabled(true)
        } else if store.answerability(for: message.id) == .open {
            // Timing changes only when the deadline passes. A per-second clock here rebuilt the
            // options, option images and reply field every second.
            TimelineView(.explicit(DecisionTiming.refreshDates(for: message))) { context in
                let timing = DecisionTiming(message: message, now: context.date)
                pendingDecision(for: message, timing: timing)
            }
        } else if message.isDecision {
            resolvedDecision(for: message)
        }
    }

    private func pendingDecision(for message: HistoryMessage, timing: DecisionTiming) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            DecisionTimingView(timing: timing, messageID: message.id)
                .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.signalSoft, in: RoundedRectangle(cornerRadius: Radius.medium))
            OptionMediaComparison(
                options: message.options,
                media: message.metadata?.optionMedia ?? [], metadata: message.metadata
            )
            if let form = message.metadata?.form {
                // A form ask takes only its structured answer; a text reply would be refused.
                AskFormView(form: form, isSubmitting: submitting != nil, onSubmit: { answers, summary in
                    await submitForm(summary, answers: answers, for: message.id)
                }, onAnswered: { dismiss() })
            } else {
                if !message.options.isEmpty {
                    DecisionOptions(options: message.options, metadata: message.metadata, timing: timing,
                                    submitting: submitting,
                                    locksControls: store.replyGate.locksControls(for: message.id),
                                    fullWidth: true) {
                        submit($0, for: message.id)
                    }
                }
                replyField(for: message)
            }
            if store.replyGate.verificationTimedOut.contains(message.id) {
                Text("This is taking longer than expected.").font(.footnote).foregroundStyle(Theme.ink2)
            } else if submitting != nil && !store.replyGate.verifying.contains(message.id) {
                ReplyPendingNote(onSettings: openSettings)
            }
        }
    }

    private func resolvedDecision(for message: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let settlement {
                ResolvedBanner(settlement: settlement, date: reply?.createdDate,
                               optionDescription: message.metadata?.optionDescription(for: settlement.answer))
            }
            Text("Options").hbLabel().foregroundStyle(Theme.ink2)
            OptionMediaComparison(
                options: message.options,
                media: message.metadata?.optionMedia ?? [], metadata: message.metadata,
                settlement: settlement
            )
            ResolvedOptionList(options: message.options, metadata: message.metadata, settlement: settlement,
                               showsCustomAnswer: true)
            .hbCard()
            decisionFooter(for: message)?.font(.hbFootnote).foregroundStyle(Theme.ink2)
        }
    }

    private func replyField(for message: HistoryMessage) -> some View {
        HStack(alignment: .bottom, spacing: Space.xs) {
            TextField("Reply…", text: draftBinding, axis: .vertical)
                .accessibilityIdentifier("message-reply-draft")
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .frame(minHeight: ControlMetric.fullWidth + Space.m)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.medium,
                                                               style: .continuous))
            Button { submit(replyDraft, for: message.id) } label: {
                Text("Send").opacity(submitting == nil ? 1 : 0)
                    .frame(minHeight: ControlMetric.fullWidth)
                    .overlay { if submitting != nil { DelayedProgressView() } }
                    .accessibilityLabel("Send")
            }
            .hbButton(.secondary, alignment: .center)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(store.replyGate.locksControls(for: message.id)
                      || replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        return Text("No longer open")
    }

    /// A form answer: true when accepted, so the form shows "Answer sent" before the view closes.
    private func submitForm(_ summary: String, answers: PanelValue, for id: MessageID) async -> Bool {
        actionNote = nil
        switch await store.reply(summary, answers: answers, to: id) {
        case .sent:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        case .alreadyResolved:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            actionNote = String(localized: "No longer open")
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            actionNote = store.replyFeedback[id] ?? store.loadError
                ?? String(localized: "Couldn't send your reply. Try again.")
        case .busy:
            break
        }
        return false
    }

    private func submit(_ choice: String, answers: PanelValue? = nil, for id: MessageID) {
        let text = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, store.replying[id] == nil else { return }
        actionNote = nil
        Task {
            switch await store.reply(text, answers: answers, to: id) {
            case .busy:
                break
            case .sent:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            case .alreadyResolved:
                // Don't claim success: refresh re-renders into the resolved branch
                // showing the answer that actually won.
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                actionNote = String(localized: "No longer open")
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                actionNote = store.replyFeedback[id] ?? store.loadError
                    ?? String(localized: "Couldn't send your reply. Try again.")
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
