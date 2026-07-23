// Session detail sheet: the messages of one session, each openable to reply.
// Exports: SessionDetailView presented from a SessionCard.
// Dependencies: SwiftUI, HibossKit, HistoryRow, ReplySheet, theme tokens.

import HibossKit
import SwiftUI

struct SessionDetailView: View {
    let group: SessionGroup
    @ObservedObject var store: InboxStore
    @Environment(\.dismiss) private var dismiss
    @State private var replyTarget: HistoryMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(group.messages) { message in
                        Button { replyTarget = message } label: { HistoryRow(message: message) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .sheet(item: $replyTarget) { message in
            ReplySheet(message: message) { choice in
                Task { await store.reply(choice, to: message.id) }
            }
            .presentationDetents([.height(300)])
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(statusColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.label).font(.hbH3).foregroundStyle(Theme.ink).lineLimit(1)
                Text(subtitle).font(.hbMonoSmall).foregroundStyle(Theme.ink3).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface2)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let agent = group.agentName { parts.append(agent) }
        if !group.statusWord.isEmpty { parts.append(group.statusWord.capitalized) }
        parts.append("\(group.messages.count) messages")
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch group.statusWord {
        case "working": Theme.positive
        case "waiting", "blocked": Theme.warn
        default: Theme.ink4
        }
    }
}
