// Shared loading / error / empty / content gate for store-backed list screens.
// Exports: ListStateView and ListStatePhase — a spinner before first load, a retryable error
// with nothing to show, an empty state, else content with a stale banner after a failed fetch.
// Dependencies: SwiftUI.

import SwiftUI

/// What a store-backed list shows. A failed fetch over earlier results is `.content` with
/// `staleError` set, so it never reads as a fresh, successful load.
enum ListStatePhase: Equatable {
    case loading
    case unreachable(String)
    case empty
    case content(staleError: String?)

    static func resolve(isLoading: Bool, error: String?, isEmpty: Bool) -> ListStatePhase {
        if isLoading { return .loading }
        if isEmpty { return error.map(ListStatePhase.unreachable) ?? .empty }
        return .content(staleError: error)
    }
}

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
        switch ListStatePhase.resolve(isLoading: isLoading, error: error, isEmpty: isEmpty) {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unreachable(error):
            ContentUnavailableView {
                Label("Can't reach the server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(verbatim: error)
            } actions: {
                Button("Retry") { Task { await onRetry() } }
            }
        case .empty:
            ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyDetail))
        case let .content(staleError):
            // Bottom, like Mail's update status: a top inset would cover the large title.
            content().safeAreaInset(edge: .bottom, spacing: 0) {
                if let staleError { staleBanner(staleError) }
            }
        }
    }

    private func staleBanner(_ error: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't reach the server. Showing earlier results.")
                    .font(.hbCallout)
                    .foregroundStyle(Theme.ink)
                Text(verbatim: error)
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink2)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("list-stale-banner")
    }
}
