// Today workspace: one focus decision card, other decisions as rows, and a context inspector.
// Exports: TodayView; running panels are summarised here and open in Watching.
// Dependencies: SwiftUI, HibossKit, TodayDecisionCard/Row, TodaySummary, TodayWatchingSummary, TodayDecisionContext.

import HibossKit
import SwiftUI

struct TodayView: View {
    let snapshot: OverviewSnapshot
    @ObservedObject var reply: AttentionReplyState
    @ObservedObject var panels: PanelsModel
    var isPreview = false
    let onChoose: (String, MessageID) async -> ReplyFeedback?
    let onSession: (String) -> Void
    var onWatching: () -> Void = {}
    @State private var selection: MessageID?
    @State private var compactDetail = false

    /// The inspector always describes the focus card's decision.
    private var selected: AttentionItem? {
        let focus = TodayDecisionFocus.focusID(snapshot.today.decisions, selection: selection)
        return snapshot.today.decisions.first { $0.id == focus }
    }

    /// The inspector column appears only with something to show; an empty "Select a
    /// question" pane would take space and say nothing, so Today uses the full width.
    var hasInspectorContent: Bool { selected != nil }

    /// Only running panels; loading, failures and filters belong to the Watching destination.
    var showsWatchingSummary: Bool { !isPreview && !WatchingRoute.running(panels.tiles).isEmpty }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760, hasInspectorContent {
                HSplitView {
                    content.frame(minWidth: 360, maxWidth: .infinity)
                    inspector.frame(minWidth: 320, idealWidth: 360, maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if compactDetail, selected != nil {
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
        .task { if !isPreview { await panels.loadIfNeeded() } }
        .accessibilityIdentifier("today.workspace")
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                TodaySummary(snapshot: snapshot.today, now: snapshot.now)
                if snapshot.today.isAllClear { TodayScene() }
                if !snapshot.today.decisions.isEmpty { decisions }
                if showsWatchingSummary { TodayWatchingSummary(panels: panels, onShowAll: onWatching) }
                TodayActivity(snapshot: snapshot.today, now: snapshot.now, onSession: onSession)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var decisions: some View {
        let focus = selected?.id
        return LazyVStack(alignment: .leading, spacing: 8) {
            Text(L("Your call")).font(.headline).padding(.bottom, 4)
            ForEach(snapshot.today.decisions) { item in
                if item.id == focus {
                    focusCard(item)
                } else {
                    TodayDecisionRow(item: item, now: snapshot.now) { selection = item.id }
                }
            }
        }
    }

    /// The full card with choices; the inspector beside it shows context only.
    @ViewBuilder
    private func focusCard(_ item: AttentionItem) -> some View {
        TodayDecisionCard(item: item, now: snapshot.now,
            isSubmitting: reply.submitting.contains(item.id),
            error: reply.errors[item.id]?.choiceText,
            onSelect: { selection = item.id; compactDetail = true },
            onChoose: { send($0, for: item.id) }, reply: reply)
            .disabled(snapshot.answerability.state(for: item.id) != .open)
            .padding(.bottom, 4)
        if snapshot.answerability.state(for: item.id) == .checking {
            Text(L("Checking…")).font(.caption).foregroundStyle(TodayStyle.secondary)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let selected {
            TodayDecisionContext(item: selected, now: snapshot.now,
                earlier: earlier(for: selected), onOpenSession: {
                    onSession(SessionGrouping.sessionKey(for: selected.message))
                })
                .disabled(reply.submitting.contains(selected.id)
                    || snapshot.answerability.state(for: selected.id) != .open)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AttentionReplyComposer(text: Binding(
                        get: { reply.drafts[selected.id] ?? "" },
                        set: { reply.drafts[selected.id] = $0 }
                    ), question: selected.message.messageText.title,
                        isSubmitting: reply.submitting.contains(selected.id),
                        error: reply.errors[selected.id]?.text,
                        onSend: { send(reply.drafts[selected.id] ?? "", for: selected.id) })
                }
                .disabled(snapshot.answerability.state(for: selected.id) != .open)
                .background(TodayStyle.surface)
                .accessibilityIdentifier("today.inspector")
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

    private func send(_ text: String, for id: MessageID) {
        guard snapshot.answerability.state(for: id) == .open else { return }
        Task { await reply.send(text, for: id, using: onChoose) }
    }
}
