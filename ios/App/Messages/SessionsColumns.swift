// The Sessions tab: one pushing stack, or the session list beside the selected item's feed.
// Exports: SessionsColumns. The shell owns the path, so deep links and rotation keep the item.
// Dependencies: SwiftUI, HibossKit, ActivityView, TwoColumnSplit and the Sessions destinations.

import HibossKit
import SwiftUI

struct SessionsColumns: View {
    let inbox: InboxStore
    let connection: ConnectionStore
    let panels: PanelsModel
    let sessionAPI: (any SessionStreamServing)?
    let listWidth: CGFloat?
    @Binding var path: NavigationPath
    @Binding var section: ActivitySection
    /// The first item in the path, highlighted in the list while two columns show.
    @State private var selected: AnyHashable?

    private var isSplit: Bool { listWidth != nil }

    var body: some View {
        TwoColumnSplit(listWidth: listWidth) {
            // Split, the list never pushes: its rows select into the detail column's path.
            NavigationStack(path: isSplit ? .constant(NavigationPath()) : $path) {
                destinations(ActivityView(store: inbox, section: $section, connection: connection))
            }
            .environment(\.routeSelection, isSplit ? RouteSelection(selected: selected, select: select) : nil)
        } detail: {
            NavigationStack(path: $path) {
                destinations(ContentUnavailableView(
                    "Select a session", systemImage: "bubble.left.and.bubble.right",
                    description: Text("Its feed opens here.")
                ).accessibilityIdentifier("sessions-detail-placeholder"))
            }
            .environment(\.keepsTabBar, isSplit)
        }
        .onChange(of: path.isEmpty) { _, empty in if empty { selected = nil } }
    }

    private func select(_ value: any Hashable) {
        var next = NavigationPath()
        next.append(value)
        path = next
    }

    private func destinations(_ root: some View) -> some View {
        root
            .navigationDestination(for: MessageID.self) {
                tracked(MessageDetailView(store: inbox, messageID: $0), value: $0)
            }
            .navigationDestination(for: SessionRoute.self) {
                tracked(SessionMessagesView(route: $0, api: sessionAPI, store: inbox, panels: panels), value: $0)
            }
            .navigationDestination(for: ResolvedRoute.self) {
                tracked(ResolvedDecisionsView(store: inbox), value: $0)
            }
    }

    /// The detail column's first screen has nothing to go back to, so it shows no back button.
    private func tracked(_ view: some View, value: some Hashable) -> some View {
        view
            .navigationBarBackButtonHidden(isSplit && path.count <= 1)
            // A push hides an iPad's tab bar; beside the list that would leave no way to other tabs.
            .toolbar(isSplit ? .visible : .automatic, for: .tabBar)
            .onAppear { if path.count == 1 { selected = AnyHashable(value) } }
    }
}
