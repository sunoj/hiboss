// Shared loading / error / empty / content gate for store-backed list screens.
// Exports ListStateView and ListStatePhase, retaining cached rows during refresh and failure.
// Dependencies: SwiftUI, PendingStateView, RetryButton and Theme.

import SwiftUI

/// What a store-backed list shows. A failed fetch over earlier results is `.content` with
/// `staleError` set, so it never reads as a fresh, successful load.
enum ListStatePhase: Equatable {
    case loading
    case unreachable(String)
    case empty
    case content(staleError: String?)

    static func resolve(
        isLoading: Bool, error: String?, isEmpty: Bool, hasLoaded: Bool = false
    ) -> ListStatePhase {
        if isEmpty && !hasLoaded, let error { return .unreachable(error) }
        if isLoading && isEmpty && !hasLoaded { return .loading }
        if isEmpty { return hasLoaded ? .empty : error.map(ListStatePhase.unreachable) ?? .empty }
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
    var loadingTitle: String = String(localized: "Loading messages…")
    var hasLoaded = false
    var reconnecting = false
    let onRetry: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch ListStatePhase.resolve(
            isLoading: isLoading, error: error, isEmpty: isEmpty, hasLoaded: hasLoaded
        ) {
        case .loading:
            ScrollView {
                PendingStateView(title: loadingTitle, showsPlaceholder: true, onRetry: onRetry)
                    .padding(16)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unreachable(error):
            ContentUnavailableView {
                Label("Can't reach the server", systemImage: "wifi.exclamationmark")
            } description: {
                Text(verbatim: error)
            } actions: {
                RetryButton(action: onRetry)
            }
        case .empty:
            ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyDetail))
                .safeAreaInset(edge: .bottom, spacing: 0) { cachedNotice }
        case .content:
            content().safeAreaInset(edge: .bottom, spacing: 0) { cachedNotice }
        }
    }

    private var cachedNotice: some View {
        CompactRefreshNotice(isRefreshing: isLoading || reconnecting, error: error,
                             title: String(localized: "Refreshing. Showing earlier results."),
                             onRetry: onRetry, statusIdentifier: "list-stale-banner")
    }
}
