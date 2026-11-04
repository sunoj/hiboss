// Shared loading / error / empty / content gate for store-backed list screens.
// Exports ListStateView, ListStatePhase and ListRefreshNotice for cached native lists.
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
    var embedsInList = false
    let onRetry: () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        switch ListStatePhase.resolve(
            isLoading: isLoading, error: error, isEmpty: isEmpty, hasLoaded: hasLoaded
        ) {
        case .loading:
            if embedsInList {
                PendingStateView(title: loadingTitle, showsPlaceholder: true, onRetry: onRetry)
                    .padding(Space.m)
            } else {
                ScrollView {
                    PendingStateView(title: loadingTitle, showsPlaceholder: true, onRetry: onRetry)
                        .padding(Space.m)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        ListRefreshNotice(isRefreshing: isLoading, error: error, reconnecting: reconnecting, onRetry: onRetry)
    }
}

struct ListRefreshNotice: View {
    let isRefreshing: Bool
    let error: String?
    var reconnecting = false
    let onRetry: () async -> Void

    var body: some View {
        CompactRefreshNotice(isRefreshing: isRefreshing || reconnecting, error: error,
                             title: reconnecting && !isRefreshing
                                ? String(localized: "Reconnecting transcript. Showing earlier events.")
                                : String(localized: "Refreshing. Showing earlier results."),
                             onRetry: onRetry, statusIdentifier: "list-stale-banner")
    }
}
