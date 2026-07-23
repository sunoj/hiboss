// Full-text detail for a single message, with reply and a jump to its session.
// Exports: MessageDetailView, SessionMessagesView, SessionRoute nav value.
// Dependencies: SwiftUI, HibossKit, HistoryRow.

import HibossKit
import SwiftUI

/// Navigation value for drilling into a session's messages.
struct SessionRoute: Hashable {
    let id: String
    let label: String
}

struct MessageDetailView: View {
    @ObservedObject var store: InboxStore
    let messageID: MessageID
    @State private var replyDraft = ""

    private var message: HistoryMessage? { store.history.first { $0.id == messageID } }

    var body: some View {
        if let message {
            Form {
                Section {
                    Text(message.body)
                        .font(.body)
                        .textSelection(.enabled)
                }

                if message.isPendingDecision {
                    Section("Respond") {
                        ForEach(message.options, id: \.self) { option in
                            Button(option) { Task { await store.reply(option, to: message.id) } }
                        }
                        HStack {
                            TextField("Reply…", text: $replyDraft, axis: .vertical)
                            Button("Send") {
                                let text = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                Task { await store.reply(text, to: message.id) }
                                replyDraft = ""
                            }
                            .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

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
            ContentUnavailableView(
                "Message not found",
                systemImage: "questionmark.circle",
                description: Text("It may have been cleared. Pull to refresh the Inbox.")
            )
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
