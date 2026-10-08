// Home tab: a glanceable, actionable attention surface.
// Exports: HomeView bound to InboxStore and message/session detail destinations.
// Dependencies: SwiftUI, InboxStore, AttentionModel, HomeAttentionSection, and PanelsModel.

import HibossKit
import SwiftUI
import UIKit

// Message rows push MessageID onto the Home tab's own NavigationStack.
struct HomeView: View {
    @ObservedObject var inbox: InboxStore
    let sessionAPI: (any SessionStreamServing)?
    @ObservedObject var panels: PanelsModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openConnectionSettings) private var openSettings
    @State private var actionNote: String?
    @State private var sessionRoute: SessionRoute?

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
            .navigationDestination(for: SessionRoute.self) {
                SessionMessagesView(route: $0, api: sessionAPI, store: inbox)
            }
            .navigationDestination(item: $sessionRoute) {
                SessionMessagesView(route: $0, api: sessionAPI, store: inbox)
            }
            .sheet(isPresented: Binding(
                get: { panels.selectedTile != nil },
                set: { if !$0 { panels.closeDetail() } }
            )) {
                if let tile = panels.selectedTile { HomePanelDetail(tile: tile, model: panels) }
            }
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
            statusIsFailure: hasCoverageFailure,
            onRetry: retryCoverage,
            onSettings: openSettings,
            replying: inbox.replying,
            onChoose: handleReply,
            onOpenPanel: openPanel,
            onOpenSession: { sessionRoute = $0 }
        )
    }

    var attentionStatus: String? {
        if let connectionNotice = HomeConnectionStatus.notice(for: inbox.connectionState) {
            return connectionNotice
        }
        if let error = inbox.requiredInputError ?? inbox.loadError
            ?? panels.questionnaireError ?? panels.failureMessage {
            if !inbox.requiredInputs.isEmpty || !panels.visibleTiles.isEmpty {
                let failure = String(
                    localized: "Couldn't check all requests. Showing earlier results. \(error)")
                return namedFailure(failure)
            }
            return namedFailure(String(localized: "Couldn't check all requests. \(error)"))
        }
        let sources = outstandingSources
        guard !sources.isEmpty else { return nil }
        return String(localized: "Waiting for: \(sources.formatted(.list(type: .and))).")
    }

    private func namedFailure(_ failure: String) -> String {
        let sources = outstandingSources.formatted(.list(type: .and))
        let waiting = String(localized: "Waiting for: \(sources).")
        return waiting + " " + failure
    }

    private var outstandingSources: [String] {
        var sources: [String] = []
        if !inbox.requiredInputReady { sources.append(String(localized: "Requests connection")) }
        else if !inbox.hasCompleteRequiredInputs { sources.append(String(localized: "Requests")) }
        if !inbox.didLoad || inbox.isRefreshing || inbox.loadError != nil {
            sources.append(String(localized: "Messages"))
        }
        if panels.loadState != .loaded || panels.isRefreshing
            || panels.tiles.contains(where: { displayedPanelFreshness($0, model: panels).isPending }) {
            sources.append(String(localized: "Panels"))
        }
        if !panels.hasCompleteQuestionnaires || panels.questionnaireError != nil {
            sources.append(String(localized: "Questionnaires"))
        }
        return sources
    }

    private var hasCoverageFailure: Bool {
        inbox.requiredInputError != nil || inbox.loadError != nil
            || panels.questionnaireError != nil || panels.failureMessage != nil
            || HomeConnectionStatus.isFailure(inbox.connectionState)
    }

    private func retryCoverage() async {
        if inbox.connectionState != .connected { inbox.retryConnection() }
        else { inbox.retryRequiredInputConnection() }
        async let messages: Void = inbox.refresh()
        async let wall: Void = panels.retryLoading()
        _ = await (messages, wall)
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
