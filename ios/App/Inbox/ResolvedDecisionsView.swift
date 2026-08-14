// Handled decisions: a dedicated list pushed from the Inbox footer.
// Exports: ResolvedDecisionsView, ResolvedDayGrouping.
// Dependencies: SwiftUI, HibossKit, InboxStore, DecisionSettlement.

import HibossKit
import SwiftUI

struct ResolvedDayGroup: Identifiable, Equatable {
    let day: Date
    var id: Date { day }
    let messages: [HistoryMessage]
}

enum ResolvedDayGrouping {
    /// Newest day first; within a day, newest decision first.
    static func groups(
        from messages: [HistoryMessage],
        calendar: Calendar = .current
    ) -> [ResolvedDayGroup] {
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.createdDate ?? .distantPast)
        }
        return grouped.keys.sorted(by: >).map { day in
            let ordered = (grouped[day] ?? []).sorted {
                ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast)
            }
            return ResolvedDayGroup(day: day, messages: ordered)
        }
    }
}

/// Pushed by value like every other route. An `isPresented`-based destination in the same
/// stack swallowed subsequent value pushes, so tapping any row re-opened this screen.
struct ResolvedRoute: Hashable {}

struct ResolvedDecisionsView: View {
    @ObservedObject var store: InboxStore

    private var cards: [HistoryMessage] {
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_RESOLVED_EMPTY"] == "1" {
            return []
        }
        return store.settledCards
    }

    private var groups: [ResolvedDayGroup] {
        ResolvedDayGrouping.groups(from: cards)
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No handled decisions",
                    systemImage: "checkmark.circle",
                    description: Text("Handled decisions will appear here.")
                )
            } else {
                list
            }
        }
        .navigationTitle("Resolved")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
    }

    private var list: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.messages) { message in
                        NavigationLink(value: message.id) {
                            ResolvedDecisionRow(
                                message: message,
                                settlement: store.settlement(for: message.id),
                                when: settledWhen(message)
                            )
                        }
                    }
                } header: {
                    Text(group.day, style: .date)
                }
            }
        }
    }

    /// Prefer the reply's time — that's when the decision was handled.
    private func settledWhen(_ message: HistoryMessage) -> String {
        if let reply = store.history.first(where: { $0.replyTo == message.id.rawValue }),
           !reply.relativeCreatedAt.isEmpty {
            return reply.relativeCreatedAt
        }
        return message.relativeCreatedAt
    }
}

struct ResolvedDecisionRow: View {
    let message: HistoryMessage
    let settlement: DecisionSettlement?
    let when: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !when.isEmpty {
                    Text(when)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(message.body)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)
            if let settlement {
                settlementBlock(settlement)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func settlementBlock(_ settlement: DecisionSettlement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(settlement.answer, systemImage: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
            if settlement.answeredElsewhere, let source = settlement.sourceLabel {
                Text("Answered on \(source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Answered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
