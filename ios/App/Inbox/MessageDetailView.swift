// Full-text detail for a single message, with reply and a jump to its session.
// Exports: MessageDetailView, SessionMessagesView, SessionRoute nav value.
// Dependencies: SwiftUI, HibossKit, HistoryRow.

import HibossKit
import SwiftUI
import UIKit

/// Navigation value for drilling into a session's messages.
struct SessionRoute: Hashable {
    let id: String
    let label: String
}

struct MessageDetailView: View {
    @ObservedObject var store: InboxStore
    let messageID: MessageID
    @State private var replyDraft = ""
    @State private var submitting: String?
    @State private var fallback: Fallback = .loading
    @State private var loadAttempt = 0
    @Environment(\.dismiss) private var dismiss

    /// What to show when the message isn't (yet) in history.
    private enum Fallback { case loading, missing }

    private var message: HistoryMessage? { store.history.first { $0.id == messageID } }

    /// The boss reply that resolved this decision, if it's in the loaded history.
    private var reply: HistoryMessage? {
        store.history.first { $0.replyTo == messageID.rawValue }
    }

    /// The chosen option text, trimmed and non-empty, or nil if unresolved.
    private var chosenAnswer: String? {
        guard let body = reply?.body.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else { return nil }
        return body
    }

    /// Human label for where the decision was resolved, e.g. "iOS", "Telegram".
    private var resolutionSourceLabel: String? {
        switch reply?.metadata?.source?.lowercased() {
        case "ios": "iOS"
        case "macos", "mac": "Mac"
        case "telegram": "Telegram"
        case "discord": "Discord"
        case "api": "API"
        case let other?: other.capitalized
        case nil: nil
        }
    }

    var body: some View {
        if let message {
            Form {
                Section {
                    Text(message.body)
                        .font(.body)
                        .textSelection(.enabled)
                }

                decisionSection(for: message)

                Section("Details") {
                    LabeledContent("Agent", value: message.displayName)
                    LabeledContent("Direction", value: directionLabel(message.direction))
                    LabeledContent("Priority", value: message.priority.capitalized)
                    if let channel = message.channel, !channel.isEmpty {
                        LabeledContent("Channel", value: channel.capitalized)
                    }
                    LabeledContent("Status", value: message.status.capitalized)
                }

                if let session = sessionRoute(for: message) {
                    Section {
                        NavigationLink(value: session) {
                            Label("View session · \(session.label)", systemImage: "square.stack.3d.up")
                        }
                    }
                }
            }
            .navigationTitle(message.displayName)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            fallbackView
        }
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
            ContentUnavailableView {
                Label("Message not found", systemImage: "questionmark.circle")
            } description: {
                Text(store.loadError == nil
                    ? "It may have been cleared or expired."
                    : "Couldn't reach the server.")
            } actions: {
                Button("Retry") { fallback = .loading; loadAttempt += 1 }
            }
        }
    }

    /// Polls for the store to become ready, refreshes, and only declares the
    /// message missing after a clean successful load that still lacks the id.
    /// Waiting for readiness is network-free; once ready we refresh at most a
    /// couple of times so a down server isn't hammered before showing the error.
    private func load() async {
        var errorAttempts = 0
        for _ in 0..<10 {
            if Task.isCancelled { return }
            if store.isReady {
                await store.refresh()
                if Task.isCancelled { return }          // cancelled once the message branch renders
                if message != nil { return }            // body re-renders into the message branch
                if store.loadError == nil { break }     // connected + clean load, genuinely absent
                errorAttempts += 1
                if errorAttempts >= 2 { break }         // don't hammer a failing server
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        if !Task.isCancelled, message == nil { fallback = .missing }
    }

    /// Options UI: interactive buttons while pending, a read-only picked/others
    /// list once resolved (with the chosen option checked and its source noted).
    @ViewBuilder private func decisionSection(for message: HistoryMessage) -> some View {
        if message.isPendingDecision {
            Section("Respond") {
                ForEach(message.options, id: \.self) { option in
                    Button {
                        submit(option, for: message.id)
                    } label: {
                        HStack {
                            Text(option)
                            if option == message.defaultOption {
                                Text("Default").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if submitting == option { ProgressView() }
                        }
                    }
                    .disabled(submitting != nil)
                }
                HStack {
                    TextField("Reply…", text: $replyDraft, axis: .vertical)
                        .disabled(submitting != nil)
                    Button("Send") { submit(replyDraft, for: message.id) }
                        .disabled(submitting != nil || replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } else if message.isDecision {
            Section {
                ForEach(message.options, id: \.self) { option in
                    optionRow(option, chosen: option == chosenAnswer)
                }
                if let answer = chosenAnswer, !message.options.contains(answer) {
                    optionRow(answer, chosen: true, custom: true)
                }
            } header: {
                Text("Options")
            } footer: {
                decisionFooter(for: message)
            }
        }
    }

    @ViewBuilder private func optionRow(_ text: String, chosen: Bool, custom: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(chosen ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).foregroundStyle(chosen ? .primary : .secondary)
                if custom { Text("Custom reply").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if chosen { Text("Selected").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func decisionFooter(for message: HistoryMessage) -> Text? {
        if chosenAnswer != nil {
            if let source = resolutionSourceLabel { return Text("Answered on \(source)") }
            return Text("Answered")
        }
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
        guard !text.isEmpty, submitting == nil else { return }
        submitting = text
        Task {
            let ok = await store.reply(text, to: id)
            submitting = nil
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
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

    private func directionLabel(_ raw: String) -> String {
        switch raw {
        case "agent_to_boss": "Agent → Boss"
        case "boss_to_agent": "Boss → Agent"
        case "agent_to_agent": "Agent → Agent"
        default: raw
        }
    }
}

/// The messages belonging to one session, each drilling into its detail.
struct SessionMessagesView: View {
    @ObservedObject var store: InboxStore
    let route: SessionRoute

    private var messages: [HistoryMessage] {
        store.history.filter { $0.sessionId?.trimmingCharacters(in: .whitespaces) == route.id }
    }

    var body: some View {
        List {
            ForEach(messages) { message in
                NavigationLink(value: message.id) { HistoryRow(message: message) }
            }
        }
        .listStyle(.plain)
        .navigationTitle(route.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
