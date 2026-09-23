// Home tab: a glanceable, actionable attention surface.
// Exports: HomeView bound to InboxStore and message/session detail destinations.
// Dependencies: SwiftUI, InboxStore, AttentionModel, HomeAttentionSection, and PanelsModel.

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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    inbox.refreshHistory()
                    Task { await panels.load() }
                }
            }
            .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
            .navigationDestination(for: SessionRoute.self) { SessionMessagesView(route: $0, api: sessionAPI) }
            .alert(
                "Heads up",
                isPresented: Binding(get: { actionNote != nil }, set: { if !$0 { actionNote = nil } }),
                presenting: actionNote
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { note in
                Text(note)
            }
    }

    @ViewBuilder
    private var content: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(spacing: 22) {
                    attentionContent(now: context.date)
                    HomePanelWall(model: panels)
                }
                .padding(.vertical, 12)
            }
        }
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
            onOpen: { AppRouter.shared.open(messageID: $0.rawValue) },
            onOpenPanel: openPanel
        )
    }

    var attentionStatus: String? {
        if let error = inbox.requiredInputError ?? inbox.loadError ?? panels.questionnaireError ?? panels.failureMessage {
            return "Couldn't check all requests. \(error) Pull to refresh."
        }
        if !inbox.didLoad || !inbox.hasCompleteRequiredInputs
            || panels.loadState != .loaded || !panels.hasCompleteQuestionnaires {
            return "Checking for requests…"
        }
        return nil
    }

    private func openPanel(_ id: String) {
        guard panels.tiles.contains(where: { $0.id == id }) else {
            actionNote = "This panel isn't available yet. Pull to refresh and try again."
            return
        }
        panels.open(id)
    }

    private func handleReply(_ choice: String, to id: MessageID) {
        Task {
            switch await inbox.reply(choice, to: id) {
            case .sent:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .alreadyResolved:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                actionNote = String(localized: "That decision was already answered elsewhere.")
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                actionNote = String(localized: "Couldn't send your reply — check your connection.")
            }
        }
    }
}
