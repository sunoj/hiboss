// Home tab: welcome header, activity heat grid, project cards, needs-you list.
// Exports: HomeView bound to HomeStore with deep-links into Inbox destinations.
// Dependencies: SwiftUI, HibossKit, HomeActivityGrid / Project / Attention.

import HibossKit
import SwiftUI

struct HomeView: View {
    @ObservedObject var store: HomeStore
    @ObservedObject var inbox: InboxStore
    let sessionAPI: (any SessionStreamServing)?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.showsError {
                ContentUnavailableView {
                    Label("Can't reach the server", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(store.loadError ?? String(localized: "Something went wrong."))
                } actions: {
                    Button("Retry") { Task { await store.refresh() } }
                }
            } else if let dashboard = store.dashboard {
                dashboardScroll(dashboard)
            } else {
                ContentUnavailableView {
                    Label("Can't reach the server", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(String(localized: "Home hasn't loaded yet."))
                } actions: {
                    Button("Retry") { Task { await store.refresh() } }
                }
            }
        }
        .background(Theme.paper)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .navigationDestination(for: MessageID.self) { MessageDetailView(store: inbox, messageID: $0) }
        .navigationDestination(for: SessionRoute.self) { SessionMessagesView(route: $0, api: sessionAPI) }
    }

    private func dashboardScroll(_ dashboard: HomeDashboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                welcomeHeader(dashboard)
                HomeActivityGrid(activity: dashboard.activity)
                    .padding(.horizontal, 16)
                HomeProjectStrip(projects: dashboard.projects)
                HomeAttentionSection(items: dashboard.attention)
            }
            .padding(.vertical, 12)
        }
    }

    private func welcomeHeader(_ dashboard: HomeDashboard) -> some View {
        let name = dashboard.boss.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let greeting = name.isEmpty
            ? String(localized: "Welcome back")
            : String(localized: "Welcome back, \(name)")
        let pending = dashboard.kpis.pendingDecisions
        return HStack(alignment: .firstTextBaseline) {
            Text(greeting)
                .font(.hbH2)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            if pending > 0 {
                Text("\(pending)")
                    .font(.hbCaption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.warn, in: Capsule())
                    .accessibilityLabel("\(pending) pending decisions")
            }
        }
        .padding(.horizontal, 16)
    }
}
