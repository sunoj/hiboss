// Home tab shell: refresh, loading, navigation and the decision sheet around HomeContent.
// Exports: HomeView. It does not observe the stores: a store change re-ran this body, and the
// new refresh action it created invalidated every view under Home (see HomeContent).

import HibossKit
import SwiftUI
import UIKit

// Message rows push MessageID onto the Home tab's own NavigationStack.
struct HomeView: View {
    let inbox: InboxStore
    let sessionAPI: (any SessionStreamServing)?
    let panels: PanelsModel
    @Environment(\.openConnectionSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    /// The shell owns the selection, so it survives a switch between one and two columns.
    @Binding var decisionID: MessageID?
    @Binding var showingDecision: Bool
    /// Two columns show the decision beside the cards instead of in a sheet.
    let showsDecisionInline: Bool
    @State private var actionNote: String?
    @State private var sessionRoute: SessionRoute?

    var body: some View {
        HomeContent(inbox: inbox, panels: panels, actionNote: $actionNote, decisionID: $decisionID,
                    showingDecision: $showingDecision, sessionRoute: $sessionRoute)
            .accessibilityHidden(presentsSheet.wrappedValue)
            .background(Theme.paper)
            .navigationTitle("Today")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openSettings() } label: { Image(systemName: "person.crop.circle.fill") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("today-settings")
                }
            }
            .refreshable {
                Task {
                    async let messages: Void = inbox.refresh()
                    async let wall: Void = panels.load()
                    _ = await (messages, wall)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await panels.load() }
                }
            }
            .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
            .navigationDestination(for: SessionRoute.self) {
                SessionMessagesView(route: $0, api: sessionAPI, store: inbox, panels: panels)
            }
            .navigationDestination(item: $sessionRoute) {
                SessionMessagesView(route: $0, api: sessionAPI, store: inbox, panels: panels)
            }
            .sheet(isPresented: presentsSheet) { decisionSheet }
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

    private var presentsSheet: Binding<Bool> {
        Binding(get: { showingDecision && !showsDecisionInline }, set: { showingDecision = $0 })
    }

    private var decisionSheet: some View {
        NavigationStack {
            if let decisionID {
                MessageDetailView(store: inbox, messageID: decisionID, onOpenSession: {
                    showingDecision = false
                    sessionRoute = $0
                })
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingDecision = false }
                } }
            }
        }.presentationDragIndicator(.visible)
    }
}
