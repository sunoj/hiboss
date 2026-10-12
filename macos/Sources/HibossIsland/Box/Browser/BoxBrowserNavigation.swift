// Native three-column Box navigation, with a two-column host for embedded previews.
// Exports: BoxBrowserColumns and main-window refresh labels.
// Dependencies: SwiftUI and the existing workspace destination model.

import SwiftUI

struct BoxBrowserColumns<Content: View, Detail: View>: View {
    let sidebar: AnyView?
    let content: Content
    let detail: Detail

    var body: some View {
        Group {
            if let sidebar {
                NavigationSplitView {
                    sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 280)
                } content: {
                    content.navigationSplitViewColumnWidth(min: 360, ideal: 420, max: 600)
                } detail: { detail }
                .navigationSplitViewStyle(.balanced)
            } else {
                HSplitView {
                    content
                    detail
                }
            }
        }.toolbar(removing: .sidebarToggle)
    }
}

enum MainWindowRefreshHelp {
    static func title(for destination: OverviewDestination) -> String {
        if destination == .box { return L("Refresh Box") }
        if destination == .progress { return L("Refresh progress") }
        switch destination {
        case .today: return L("Refresh Today")
        case .deviceRequests: return L("Refresh device requests")
        default: return L("Refresh messages")
        }
    }
}
