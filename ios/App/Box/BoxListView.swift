// Activity's Box segment with native state gates, pagination and swipe deletion.
// Exports BoxListView; link, text, media and file opening stays within Activity.
// Dependencies: SwiftUI, HibossKit, BoxStore, BoxMediaStore and ListStateView.

import HibossKit
import SwiftUI

struct BoxListView: View {
    @StateObject private var store: BoxStore
    @StateObject private var media: BoxMediaStore
    @State private var openedMedia: BoxItem?
    @State private var openingError = false
    @Environment(\.openURL) private var openURL
    @Environment(\.openConnectionSettings) private var openSettings

    init(api: (any BoxServing)?) {
        _store = StateObject(wrappedValue: BoxStore(api: api))
        _media = StateObject(wrappedValue: BoxMediaStore(api: api))
    }

    var body: some View {
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing, error: store.error,
            isEmpty: store.items.isEmpty, emptyIcon: "archivebox",
            emptyTitle: String(localized: "Your Box is empty"),
            emptyDetail: String(localized: "Shared links, text and media appear here."),
            loadingTitle: String(localized: "Loading Box…"), hasLoaded: store.didLoad,
            onRetry: { await store.refresh() }
        ) { list }
        .task { if !store.didLoad { await store.refresh() } }
        .refreshable { await store.refresh() }
        .fullScreenCover(item: $openedMedia) { item in BoxMediaDetail(item: item, media: media) }
        .alert("Couldn't delete item", isPresented: Binding(
            get: { store.deleteError != nil }, set: { if !$0 { store.deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
            Button("Settings", action: openSettings)
        } message: { Text(verbatim: store.deleteError ?? "") }
        .alert("Couldn't open link", isPresented: $openingError) { Button("OK", role: .cancel) {} }
    }

    private var list: some View {
        List {
            ForEach(store.items) { item in
                row(item)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task {
                                await store.delete(item)
                                if !store.items.contains(where: { $0.id == item.id }) {
                                    media.remove(id: item.id)
                                }
                            }
                        }.disabled(store.deleting.contains(item.id))
                    }
                    .overlay(alignment: .trailing) {
                        if store.deleting.contains(item.id) {
                            PendingStateView(
                                title: String(localized: "Deleting item…"), onSettings: openSettings
                            )
                                .padding(8).background(.regularMaterial)
                        }
                    }
            }
            pagination
        }
        .listStyle(.plain)
        .accessibilityIdentifier("box-list")
    }

    @ViewBuilder private func row(_ item: BoxItem) -> some View {
        if item.kind == .text || item.kind == .file {
            NavigationLink { BoxTextDetail(item: item, media: media) } label: {
                BoxRow(item: item, media: media)
            }
                .accessibilityIdentifier("box-item-\(item.id)")
        } else {
            Button {
                if item.kind == .link {
                    guard let url = item.url.flatMap(URL.init(string:)),
                          ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                        openingError = true
                        return
                    }
                    openURL(url) { accepted in openingError = !accepted }
                } else { openedMedia = item }
            } label: { BoxRow(item: item, media: media) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("box-item-\(item.id)")
        }
    }

    @ViewBuilder private var pagination: some View {
        if let error = store.pageError {
            VStack(alignment: .leading) {
                Text(verbatim: error).font(.callout).foregroundStyle(Theme.ink2)
                RetryButton { await store.retryPage() }
            }
        } else if store.isLoadingMore {
            PendingStateView(
                title: String(localized: "Loading more Box items…"), onRetry: { await store.retryPage() }
            )
        } else if store.nextCursor != nil {
            Button("Load more") { Task { await store.loadMore() } }
                .frame(minHeight: 44).accessibilityIdentifier("box-load-more")
        }
    }
}
