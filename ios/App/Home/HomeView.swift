// Home tab: a glanceable, actionable attention surface.
// Exports: HomeView bound to InboxStore and message/session detail destinations.
// Dependencies: SwiftUI, InboxStore, AttentionModel, HomeAttentionSection.

import HibossKit
import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var inbox: InboxStore
    let sessionAPI: (any SessionStreamServing)?
    @Environment(\.scenePhase) private var scenePhase
    @State private var actionNote: String?

    var body: some View {
        content
            .background(Theme.paper)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    HomeAttentionSection(
                        groups: AttentionModel.grouped(
                            from: inbox.history.filter { !inbox.withdrawn.contains($0.id) },
                            now: context.date
                        ),
                        onChoose: handleReply,
                        onOpen: { AppRouter.shared.open(messageID: $0.rawValue) }
                    )
                    .padding(.vertical, 12)
                }
            }
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
