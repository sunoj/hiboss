// Shared loading / error / empty / content gate for store-backed list screens.
// Exports: ListStateView — shows a spinner before first load, a retryable error
// state when a fetch failed with nothing to show, an empty state, else content.
// Dependencies: SwiftUI.

import SwiftUI

struct ListStateView<Content: View>: View {
    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let emptyIcon: String
    let emptyTitle: String
    let emptyDetail: String
    let onRetry: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty, let error {
            ContentUnavailableView {
                Label("Can't reach the server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await onRetry() } }
            }
        } else if isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyDetail))
        } else {
            content()
        }
    }
}
