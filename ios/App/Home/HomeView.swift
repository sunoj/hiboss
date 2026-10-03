// Home tab: a glanceable, actionable attention surface.
// Exports: HomeView bound to InboxStore and message/session detail destinations.
// Dependencies: SwiftUI, InboxStore, AttentionModel, HomeAttentionSection, and PanelsModel.
// Message rows push MessageID onto the Home tab's own NavigationStack.

import HibossKit
import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var inbox: InboxStore
    let sessionAPI: (any SessionStreamServing)?
    @ObservedObject var panels: PanelsModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var actionNote: String?

    var body: some View {
        content
            .background(Theme.paper)
            .refreshable {
                await inbox.refresh()
                await panels.load()
            }
            .task { await inbox.refresh() }
            // Panels load here, not in the wall: the wall only exists once there are tiles.
            .task { await panels.loadIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    inbox.refreshHistory()
                    Task { await panels.load() }
                }
            }
            .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
            .navigationDestination(for: SessionRoute.self) { SessionMessagesView(route: $0, api: sessionAPI, store: inbox) }
            .alert(
                "Heads up",
                isPresented: Binding(get: { actionNote != nil }, set: { if !$0 { actionNote = nil } }),
                presenting: actionNote
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { note in
                Text(verbatim: note)
            }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                // Only attention ranking depends on time; the wall keeps its own clocks.
                TimelineView(HomeRefreshSchedule(deadlines: refreshDeadlines)) { context in
                    attentionContent(now: context.date)
                }
                if !panels.tiles.isEmpty {
                    HomePanelWall(model: panels)
                }
            }
            .padding(.vertical, 12)
        }
    }

    /// Expiry moments that change the ranking; countdown text ticks on its own.
    private var refreshDeadlines: [Date] {
        inbox.requiredInputs.compactMap(\.expirationDate)
            + panels.pendingQuestionnaires.compactMap { $0.expiresAt.flatMap(ISODate.parse) }
    }

    private func attentionContent(now: Date) -> some View {
        HomeAttentionSection(
            snapshot: HomeAttentionSnapshot(
                messages: inbox.requiredInputs, withdrawn: inbox.withdrawn,
                questionnaires: panels.pendingQuestionnaires,
                terminalPanelIDs: Set(panels.tiles.filter { $0.lifecycle.taskState.isTerminal }.map(\.id)),
                now: now, panelNow: { panels.serverNow(for: $0) }
            ),
            hasPanels: !panels.visibleTiles.isEmpty,
            status: attentionStatus,
            onChoose: handleReply,
            onOpenPanel: openPanel
        )
    }

    var attentionStatus: String? {
        if let error = inbox.requiredInputError ?? inbox.loadError ?? panels.questionnaireError ?? panels.failureMessage {
            return String(localized: "Couldn't check all requests. \(error) Pull to refresh.")
        }
        if !inbox.didLoad || !inbox.hasCompleteRequiredInputs
            || panels.loadState != .loaded || !panels.hasCompleteQuestionnaires {
            return String(localized: "Checking for requests…")
        }
        return nil
    }

    private func openPanel(_ id: String) {
        guard panels.tiles.contains(where: { $0.id == id }) else {
            actionNote = String(localized: "This panel isn't available yet. Pull to refresh and try again.")
            return
        }
        panels.open(id)
    }

    private func handleReply(_ choice: String, to id: MessageID) {
        Task {
            if let note = await inbox.replyWithFeedback(choice, to: id) { actionNote = note }
        }
    }
}
