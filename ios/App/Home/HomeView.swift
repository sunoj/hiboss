// Home tab: a glanceable, actionable attention surface.
// Exports: HomeView bound to InboxStore and message/session detail destinations.
// Dependencies: SwiftUI, InboxStore, AttentionModel, HomeAttentionSection, and PanelsModel.

import HibossKit
import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var inbox: InboxStore
    let sessionAPI: (any SessionStreamServing)?
    @StateObject private var panels: PanelsModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var actionNote: String?

    init(
        inbox: InboxStore,
        sessionAPI: (any SessionStreamServing)?,
        panelConfigurationProvider: @escaping @MainActor () async throws -> ConnectionConfig
    ) {
        self.inbox = inbox
        self.sessionAPI = sessionAPI
        _panels = StateObject(wrappedValue: PanelsModel(configurationProvider: panelConfigurationProvider))
    }

    var body: some View {
        content
            .background(Theme.paper)
            .refreshable { await inbox.refresh() }
            .task { await inbox.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { inbox.refreshHistory() }
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

    @ViewBuilder
    private func attentionContent(now: Date) -> some View {
        if !inbox.didLoad && inbox.history.isEmpty {
            if inbox.connectionState == .disconnected {
                ContentUnavailableView(
                    "Disconnected",
                    systemImage: "wifi.slash",
                    description: Text("Connect in Settings to see what needs you.")
                )
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        } else if inbox.history.isEmpty, let error = inbox.loadError {
            ContentUnavailableView {
                Label("Can't reach the server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await inbox.refresh() } }
            }
        } else {
            HomeAttentionSection(
                groups: AttentionModel.grouped(
                    from: inbox.history.filter { !inbox.withdrawn.contains($0.id) },
                    now: now
                ),
                hasPanels: !panels.visibleTiles.isEmpty,
                onChoose: handleReply,
                onOpen: { AppRouter.shared.open(messageID: $0.rawValue) }
            )
        }
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
