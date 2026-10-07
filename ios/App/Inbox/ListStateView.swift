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
        if isLoading && isEmpty && !hasLoaded { return .loading }
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
    var loadingTitle: String = String(localized: "Loading messages…")
    var hasLoaded = false
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
                .safeAreaInset(edge: .bottom) { refreshingNotice }
        case let .content(staleError):
            // Bottom, like Mail's update status: a top inset would cover the large title.
            content().safeAreaInset(edge: .bottom, spacing: 0) {
                if let staleError { staleBanner(staleError) }
                else { refreshingNotice }
            }
        }
    }

    @ViewBuilder private var refreshingNotice: some View {
        if isLoading {
            PendingStateView(title: String(localized: "Refreshing. Showing earlier results."),
                             onRetry: onRetry)
                .padding(12).background(.bar)
        }
    }

    private func staleBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            RetryButton(action: onRetry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("list-stale-banner")
    }
}
