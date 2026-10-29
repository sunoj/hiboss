// Attention surface: settled empty state, or list + full context side by side.
// Exports: AttentionView and AttentionWorkspace.
// Dependencies: SwiftUI, HibossKit OptionFlowStore, AttentionModel.

import HibossKit
import SwiftUI

struct AttentionView: View {
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var reply: AttentionReplyState
    let category: OverviewCategory
    let items: [AttentionItem]
    let now: Date
    let answerability: AnswerableDecisions
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    @State private var selection: MessageID?

    var body: some View {
        content(items: items, now: now)
    }

    @ViewBuilder
    private func content(items: [AttentionItem], now: Date) -> some View {
        if !answerability.isLoaded {
            ProgressView(L("Loading"))
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
                reply: reply,
                onChoose: onChoose
            )
        }
    }

    private var settledEmpty: some View {
        ContentUnavailableView(
            category == .needsYou ? L("Nothing needs you") : L("No questions in this category"),
            systemImage: "checkmark.circle",
            description: Text(category == .needsYou
                ? L("You're clear. Agents will show up here when they need a decision.")
                : L("Choose another category to see more messages."))
        )
    }
}

struct AttentionWorkspace: View {
    let items: [AttentionItem]
    let now: Date
    @Binding var selection: MessageID?
    @ObservedObject var reply: AttentionReplyState
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    @State private var showsCompactDetail = false

    private static let splitMinimumWidth: CGFloat = 720

    private var sections: [AttentionGroupItems] {
        AttentionGroup.allCases.compactMap { group in
            let members = items.filter { $0.group == group }
            return members.isEmpty ? nil : AttentionGroupItems(group: group, items: members)
        }
    }

    private var selectedItem: AttentionItem? {
        items.first { $0.id == selection }
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= Self.splitMinimumWidth {
                HSplitView {
                    list
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    detail
                        .frame(minWidth: 360)
                }
            } else {
                compactContent
            }
        }
        .onAppear { syncSelection() }
        .onChange(of: items.map(\.id)) { syncSelection() }
        .onChange(of: selection) { showsCompactDetail = selection != nil }
    }

    private var compactContent: some View {
        VStack(spacing: 0) {
            if showsCompactDetail, selectedItem != nil {
                HStack {
                    Button {
                        showsCompactDetail = false
                    } label: {
                        Label(L("All questions"), systemImage: "chevron.left")
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
                detail
            } else {
                list
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(sections, id: \.group) { section in
                Section(section.group.title) {
                    ForEach(section.items) { item in
                        AttentionRow(item: item, now: now)
                            .tag(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = item.id
                                showsCompactDetail = true
                            }
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
                send(choice, for: selectedItem.id)
            }
            .disabled(reply.submitting.contains(selectedItem.id))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AttentionReplyComposer(
                    text: Binding(
                        get: { reply.drafts[selectedItem.id] ?? "" },
                        set: { reply.drafts[selectedItem.id] = $0 }
                    ),
                    isSubmitting: reply.submitting.contains(selectedItem.id),
                    error: reply.errors[selectedItem.id]?.text,
                    onSend: { send(reply.drafts[selectedItem.id] ?? "", for: selectedItem.id) }
                )
            }
        } else {
            ContentUnavailableView(
                L("Select a question"),
                systemImage: "hand.tap",
                description: Text(L("Full context appears here."))
            )
        }
    }

    private func send(_ text: String, for id: MessageID) {
        Task { await reply.send(text, for: id, using: onChoose) }
    }

    private func syncSelection() {
        let ids = items.map(\.id)
        if let selection, ids.contains(selection) { return }
        self.selection = ids.first
    }
}
