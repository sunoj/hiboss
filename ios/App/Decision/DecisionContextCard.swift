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
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .center, spacing: Space.s) {
                ProjectAvatarView(project: session?.avatarProject
                                  ?? inventory.project(slug: message.project ?? message.sessionLabel ?? ""),
                                  size: AvatarSize.compact)
                if let branch = message.sessionBranch {
                    Text(verbatim: branch).font(.subheadline.bold())
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            HStack {
                if let agent = message.agentName ?? session?.agentName { Text(verbatim: agent) }
                if let host = session?.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
                    Text(verbatim: host)
                }
                if let date = message.createdDate { RecordedTimeText(date: date) }
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
            .hbCard()
            .accessibilityIdentifier("decision-facts")
    }
}
