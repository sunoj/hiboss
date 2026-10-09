// Box grid with search, author/kind filters, pagination, and native context-menu deletion.
// Exports BoxListView; existing content viewers also support a reference-selection sheet.
// Dependencies: SwiftUI, HibossKit, BoxStore, BoxMediaStore and ListStateView.

import HibossKit
import SwiftUI

struct BoxListView: View {
    let onSelect: ((BoxItem) -> Void)?
    @StateObject private var store: BoxStore
    @StateObject private var media: BoxMediaStore
    @State private var search = ""
    @State private var filter = BoxFilter.all
    @State private var openedMedia: BoxItem?
    @State private var openingError = false
    @Environment(\.openURL) private var openURL
    @Environment(\.openConnectionSettings) private var openSettings

    init(api: (any BoxServing)?, onSelect: ((BoxItem) -> Void)? = nil) {
        self.onSelect = onSelect
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
        .background(Theme.paper)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search notes, links and files")
        .task {
            if !store.didLoad { await store.refresh() }
            if !search.isEmpty || filter != .all { await store.loadSearchPages() }
        }
        .task(id: search + filter.rawValue) {
            if !search.isEmpty || filter != .all { await store.loadSearchPages() }
        }
        .refreshable {
            await store.refresh()
            if !search.isEmpty || filter != .all { await store.loadSearchPages() }
        }
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
        ScrollView {
            VStack(spacing: 12) {
                BoxFilterChips(selection: $filter)
                if matches.isEmpty && !store.isLoadingMore {
                    ContentUnavailableView.search(text: search)
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top),
                                    GridItem(.flexible(), alignment: .top)], spacing: 12) {
                    ForEach(matches) { item in
                        row(item)
                            .contextMenu {
                                if onSelect == nil {
                                    Button("Delete", role: .destructive) { delete(item) }
                                        .disabled(store.deleting.contains(item.id))
                                }
                            }
                            .overlay {
                                if store.deleting.contains(item.id) {
                                    PendingStateView(title: String(localized: "Deleting item…"),
                                                     onSettings: openSettings)
                                        .padding(8).background(.regularMaterial)
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                pagination
            }.padding(.bottom, 16)
        }
        .accessibilityIdentifier("box-list")
    }

    private var matches: [BoxItem] { store.items.filter { filter.matches($0, search: search) } }

    private func delete(_ item: BoxItem) {
        Task {
            await store.delete(item)
            if !store.items.contains(where: { $0.id == item.id }) { media.remove(id: item.id) }
        }
    }

    @ViewBuilder private func row(_ item: BoxItem) -> some View {
        if let onSelect {
            Button { onSelect(item) } label: { BoxRow(item: item, media: media, grid: true) }
                .buttonStyle(.plain).accessibilityIdentifier("box-item-\(item.id)")
        } else if item.kind == .text || item.kind == .file {
            NavigationLink { BoxTextDetail(item: item, media: media) } label: {
                BoxRow(item: item, media: media, grid: true)
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
            } label: { BoxRow(item: item, media: media, grid: true) }
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
