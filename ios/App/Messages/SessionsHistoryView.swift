// History pushed from the Sessions toolbar: the full message list and completed decisions.
// Exports: SessionsHistoryView. Device requests stay in Settings › Devices.
// Dependencies: SwiftUI, RouteLink, AllMessagesRoute and ResolvedRoute.

import SwiftUI

struct SessionsHistoryView: View {
    var body: some View {
        List {
            RouteLink(value: AllMessagesRoute()) {
                Label("All messages", systemImage: "text.bubble")
                    .frame(minHeight: ControlMetric.minTap, alignment: .leading)
            }
            .accessibilityIdentifier("history-all-messages")
            RouteLink(value: ResolvedRoute()) {
                Label("Completed", systemImage: "checkmark.circle")
                    .frame(minHeight: ControlMetric.minTap, alignment: .leading)
            }
            .accessibilityIdentifier("history-completed")
        }
        .listStyle(.insetGrouped)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
