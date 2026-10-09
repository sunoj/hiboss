// Decision provenance and content facts, preserving the message's original evidence.
// Exports DecisionContextCard and DecisionProvenance; absent facts are never inferred.
// Dependencies: HibossKit HistoryMessage/ProjectSession and native text selection.

import HibossKit
import SwiftUI

struct DecisionProvenance: View {
    let message: HistoryMessage
    var session: ProjectSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: session?.displayLabel ?? [message.sessionLabel, message.sessionBranch]
                .compactMap { $0 }.joined(separator: " / ")).font(.subheadline.bold())
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
        Text(verbatim: message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
             .nilIfEmpty ?? message.body)
            .font(.subheadline).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("decision-facts")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
