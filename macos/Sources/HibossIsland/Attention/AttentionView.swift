// Attention surface: settled empty state, or list + full context side by side.
// Exports: AttentionView and AttentionWorkspace.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, AttentionRanking.

import HibossKit
import SwiftUI

struct AttentionView: View {
    @ObservedObject var flow: OptionFlowStore
    @State private var selection: MessageID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let items = AttentionRanking.items(
                history: flow.historyMessages,
                live: flow.activeMessage,
                now: context.date
            )
            content(items: items, now: context.date)
        }
        .navigationTitle(L("Needs You"))
    }

    @ViewBuilder
    private func content(items: [AttentionItem], now: Date) -> some View {
        if items.isEmpty, flow.historyState == .loading {
            ProgressView(L("Loading…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty, case let .failed(message) = flow.historyState,
                  flow.historyMessages.isEmpty {
            ContentUnavailableView(
                L("Attention Unavailable"),
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        } else if items.isEmpty {
            settledEmpty
        } else {
            AttentionWorkspace(
                items: items,
                now: now,
                selection: $selection,
                onChoose: { choice, id in
                    Task { await flow.answerHistory(choice, for: id) }
                }
            )
        }
    }

    private var settledEmpty: some View {
        ContentUnavailableView(
            L("Nothing needs you"),
            systemImage: "checkmark.circle",
            description: Text(L("You're clear. Agents will show up here when they need a decision."))
        )
    }
}

struct AttentionWorkspace: View {
    let items: [AttentionItem]
    let now: Date
    @Binding var selection: MessageID?
    let onChoose: (String, MessageID) -> Void

    private var sections: [AttentionSection] {
        AttentionRanking.grouped(items, now: now)
    }

    private var selectedItem: AttentionItem? {
        items.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
            detail
                .frame(minWidth: 400)
        }
        .onAppear { syncSelection() }
        .onChange(of: items.map(\.id)) { syncSelection() }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section(section.band.title) {
                    ForEach(section.items) { item in
                        AttentionRow(item: item, now: now)
                            .tag(item.id)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedItem {
            AttentionDetail(item: selectedItem, now: now) { choice in
                onChoose(choice, selectedItem.id)
            }
        } else {
            ContentUnavailableView(
                L("Select a question"),
                systemImage: "hand.tap",
                description: Text(L("Full context appears here."))
            )
        }
    }

    private func syncSelection() {
        let ids = items.map(\.id)
        if let selection, ids.contains(selection) { return }
        self.selection = ids.first
    }
}
