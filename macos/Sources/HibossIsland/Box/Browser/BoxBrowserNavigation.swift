// Box list and preview side by side; the window's own split holds the sidebar.
// Exports: BoxBrowserColumns and main-window refresh labels.
// Dependencies: SwiftUI and the existing workspace destination model.

import SwiftUI

struct BoxBrowserColumns<Content: View, Detail: View>: View {
    let content: Content
    let detail: Detail

    var body: some View {
        HSplitView {
            content
            detail
        }
        .toolbar(removing: .sidebarToggle)
    }
}

enum MainWindowRefreshHelp {
    static func title(for destination: OverviewDestination) -> String {
        if destination == .box { return L("Refresh Box") }
        if destination == .progress { return L("Refresh progress") }
        switch destination {
        case .today: return L("Refresh Today")
        case .deviceRequests: return L("Refresh device requests")
        case .watching: return L("Refresh panels")
        default: return L("Refresh messages")
        }
    }
}
