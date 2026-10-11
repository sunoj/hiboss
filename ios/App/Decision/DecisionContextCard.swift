// Decision provenance and content facts, preserving the message's original evidence.
// Exports DecisionContextCard and DecisionProvenance; absent facts are never inferred.
// Dependencies: HibossKit HistoryMessage/ProjectSession and native text selection.

import HibossKit
import SwiftUI

struct DecisionProvenance: View {
    let message: HistoryMessage
    var session: ProjectSession?
    @Environment(\.projectSessions) private var inventory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                ProjectAvatarView(project: session?.avatarProject
                                  ?? inventory.project(slug: message.project ?? message.sessionLabel ?? ""),
                                  size: 32)
                Text(verbatim: session?.namedLabel ?? [message.sessionLabel, message.sessionBranch]
                    .compactMap { $0 }.joined(separator: " / ")).font(.subheadline.bold())
            }
            HStack {
                if let agent = message.agentName ?? session?.agentName { Text(verbatim: agent) }
                if let host = session?.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
                    Text(verbatim: host)
                }
                if let date = message.createdDate { Text(date, style: .time) }
            }.font(.footnote).foregroundStyle(Theme.ink2)
        }
        .accessibilityIdentifier("decision-provenance")
    }
}

struct DecisionContextCard: View {
    let message: HistoryMessage

    var body: some View {
        MediaMarkdownView(message.messageText.content ?? message.body)
            .font(.subheadline).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("decision-facts")
    }
}
