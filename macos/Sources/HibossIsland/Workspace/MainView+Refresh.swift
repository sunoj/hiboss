// The main window's one refresh action, routed to the store behind the current destination.
// Exports: MainView.refresh.
// Dependencies: MainView's stores and destination.

import SwiftUI

extension MainView {
    func refresh() {
        if destination == .progress {
            Task { await progress.refresh() }
            return
        }
        if destination == .box {
            Task { await box.refresh() }
            return
        }
        if destination == .watching {
            Task { await panels.load() }
            return
        }
        if destination == .deviceRequests { Task { await joinRequests.refresh() } }
        if case .session = destination, sessionBox.project != nil { Task { await sessionBox.refresh() } }
        requiredInputs.refresh()
        Task { await flow.refreshHistory() }
        if destination == .today { Task { await panels.load() } }
    }
}
