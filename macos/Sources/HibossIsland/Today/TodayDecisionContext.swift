// Today's inspector for the focus decision: context only, since the card holds the choices.
// Exports: TodayDecisionContext (title, session facts, earlier messages, Open session).
// Dependencies: SwiftUI, HibossKit AttentionItem/ProjectSession/HistoryMessage, TodayStyle.

import HibossKit
import SwiftUI

struct TodayDecisionContext: View {
    @Environment(\.surfaceIsVisible) private var isVisible
    @Environment(\.projectSessions) private var inventory
    let item: AttentionItem
    let now: Date
    let earlier: [HistoryMessage]
    let onOpenSession: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Context")).font(.caption.weight(.semibold))
                        .foregroundStyle(TodayStyle.tertiary).textCase(.uppercase)
                    Text(verbatim: item.message.messageText.title).font(.headline)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                facts
                if !earlier.isEmpty { earlierMessages }
                Button(L("Open session"), systemImage: "arrow.up.right", action: onOpenSession)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("today.context")
    }

    private var session: ProjectSession? {
        let id = SessionGrouping.sessionKey(for: item.message)
        return inventory.first { $0.id == id }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            TimelineView(.periodic(from: now, by: 1).paused(!isVisible)) { context in
                row(L("Waiting"), item.waited(at: context.date))
            }
            row(L("Session"), item.project(in: inventory).displayName
                + (session?.branch.map { " / " + $0 } ?? ""))
            row(L("Agent"), item.asker)
            if let host = session?.host { row(L("Machine"), host) }
            if let started = session?.startedAt.flatMap(ISODate.parse) {
                row(L("Started"), SharedTimestamp.string(started, now: now))
            }
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(TodayStyle.secondary)
            Text(verbatim: value).textSelection(.enabled).lineLimit(2)
        }
    }

    private var earlierMessages: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Earlier in this session")).font(.caption.weight(.semibold))
                .foregroundStyle(TodayStyle.tertiary).textCase(.uppercase)
            ForEach(earlier) { message in
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.body).font(.callout).lineLimit(2).textSelection(.enabled)
                    if let date = ISODate.parse(message.createdAt) {
                        Text(SharedTimestamp.string(date, now: now))
                            .font(.caption).foregroundStyle(TodayStyle.tertiary)
                    }
                }
            }
        }
    }
}
