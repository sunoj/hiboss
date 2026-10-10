// Today workspace with shared decisions, work, deliveries, and an in-place inspector.
// Exports: TodayView; existing panel controls and session threads remain reachable.
// Dependencies: SwiftUI, HibossKit, TodayDecisionCard, TodaySummary, and AttentionDetail.

import HibossKit
import SwiftUI

struct TodayView: View {
    let snapshot: OverviewSnapshot
    @ObservedObject var reply: AttentionReplyState
    @ObservedObject var panels: PanelsModel
    var isPreview = false
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    let onSession: (String) -> Void
    @State private var selection: MessageID?
    @State private var compactDetail = false

    private var selected: AttentionItem? {
        snapshot.today.decisions.first { $0.id == selection }
    }

    /// The inspector column appears only with something to show; an empty "Select a
    /// question" pane would take space and say nothing, so Today uses the full width.
    var hasInspectorContent: Bool { selected != nil || panels.selectedTile != nil }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760, hasInspectorContent {
                HSplitView {
                    content.frame(minWidth: 360, maxWidth: .infinity)
                    inspector.frame(minWidth: 320, idealWidth: 360, maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if compactDetail, selected != nil || panels.selectedTile != nil {
                VStack(spacing: 0) {
                    HStack {
                        Button(L("Today"), systemImage: "chevron.left") { compactDetail = false }
                        Spacer()
                    }.padding(12)
                    Divider()
                    inspector
                }
            } else {
                content
            }
        }
        .background(TodayStyle.ground)
        .onAppear { syncSelection() }
        .onChange(of: snapshot.attention.map(\.id)) { syncSelection() }
        .onChange(of: panels.selectedTileID) { _, id in
            if id != nil { selection = nil; compactDetail = true }
        }
        .task { if !isPreview { await panels.loadIfNeeded() } }
        .accessibilityIdentifier("today.workspace")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TodaySummary(snapshot: snapshot.today, now: snapshot.now)
                if snapshot.today.isAllClear { TodayScene() }
                if !snapshot.today.decisions.isEmpty { decisions }
                if !isPreview && (!panels.visibleTiles.isEmpty || panels.failureMessage != nil) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Watching")).font(.headline)
                        DashboardPanelsSection(model: panels)
                    }
                }
                TodayActivity(snapshot: snapshot.today, now: snapshot.now, onSession: onSession)
                if !isPreview {
                    DisclosureGroup(L("Panels")) { DashboardPanelsSection(model: panels) }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var decisions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Your call")).font(.headline)
            ForEach(snapshot.today.decisions) { item in
                TodayDecisionCard(item: item, now: snapshot.now, isSelected: selection == item.id,
                    isSubmitting: reply.submitting.contains(item.id),
                    error: reply.errors[item.id]?.choiceText,
                    onSelect: { panels.closeDetail(); selection = item.id; compactDetail = true },
                    onChoose: { send($0, for: item.id) })
                    .disabled(snapshot.answerability.state(for: item.id) != .open)
                if snapshot.answerability.state(for: item.id) == .checking {
                    Text(L("Checking…")).font(.caption).foregroundStyle(TodayStyle.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let selected {
            AttentionDetail(item: selected, now: snapshot.now,
                earlier: earlier(for: selected), onOpenSession: {
                    onSession(SessionGrouping.sessionKey(for: selected.message))
                }, onChoose: { send($0, for: selected.id) })
                .disabled(reply.submitting.contains(selected.id)
                    || snapshot.answerability.state(for: selected.id) != .open)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AttentionReplyComposer(text: Binding(
                        get: { reply.drafts[selected.id] ?? "" },
                        set: { reply.drafts[selected.id] = $0 }
                    ), isSubmitting: reply.submitting.contains(selected.id),
                        error: reply.errors[selected.id]?.text,
                        onSend: { send(reply.drafts[selected.id] ?? "", for: selected.id) })
                }
                .disabled(snapshot.answerability.state(for: selected.id) != .open)
                .background(TodayStyle.surface)
                .accessibilityIdentifier("today.inspector")
        } else if let tile = panels.selectedTile {
            ScrollView { DashboardPanelDetail(tile: tile, model: panels).padding(20) }
        } else {
            ContentUnavailableView(L("Select a question"), systemImage: "sidebar.right",
                description: Text(L("Full context appears here.")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func earlier(for item: AttentionItem) -> [HistoryMessage] {
        let session = SessionGrouping.sessionKey(for: item.message)
        return Array(snapshot.history.filter {
            $0.id != item.id && SessionGrouping.sessionKey(for: $0) == session
                && (HistoryTimestamp.date(from: $0.createdAt) ?? .distantPast)
                    < (item.createdDate ?? .distantFuture)
        }.prefix(3))
    }

    private func syncSelection() {
        if panels.selectedTile != nil {
            selection = nil
            compactDetail = true
            return
        }
        if let selection, snapshot.attention.contains(where: { $0.id == selection }) { return }
        selection = snapshot.attention.first?.id
    }

    private func send(_ text: String, for id: MessageID) {
        guard snapshot.answerability.state(for: id) == .open else { return }
        Task { await reply.send(text, for: id, using: onChoose) }
    }
}
