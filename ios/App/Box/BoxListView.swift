// Box browser with combined filters, collection shortcuts and confirmed item actions.
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
    @State private var author = BoxAuthorFilter.all
    @State private var adding = false
    @State private var openedMedia: BoxMediaSelection?
    @State private var openedDetail: BoxItem?
    @State private var pendingDelete: BoxItem?
    @State private var collectionItem: BoxItem?
    @State private var liked = false
    @State private var shareItem: BoxItem?
    @Environment(\.openConnectionSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase

    init(api: (any BoxServing)?, onSelect: ((BoxItem) -> Void)? = nil,
         collectionID: String? = nil) {
        self.onSelect = onSelect
        _store = StateObject(wrappedValue: BoxStore(api: api, collectionID: collectionID))
        _media = StateObject(wrappedValue: BoxMediaStore(api: api))
    }

    var body: some View {
        content
        .background(Theme.paper)
        .toolbarTitleDisplayMode(onSelect == nil ? .inlineLarge : .automatic)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search notes, links and files")
        .task {
            if !store.didLoad { await store.refresh() }
            if !search.isEmpty || hasFilters { await store.loadSearchPages() }
        }
        .task { await store.loadCollections() }
        .task(id: search + filter.rawValue + author.rawValue + String(liked)) {
            if !search.isEmpty || hasFilters { await store.loadSearchPages() }
        }
        .refreshable { await refresh() }
        .toolbar {
            if isMainBox {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save to Box", systemImage: "plus") { adding = true }
                        .accessibilityIdentifier("box-add")
                }
            }
        }
        .sheet(isPresented: $adding) {
            BoxAddSheet(api: store.api) {
                adding = false
                Task { await refresh() }
            }
        }
        .modifier(BoxDeleteConfirmation(item: $pendingDelete, store: store, media: media))
    }

    private var isMainBox: Bool { onSelect == nil && store.collectionID == nil }

    private var hasFilters: Bool { filter != .all || author != .all || liked }

    private func refresh() async {
        await store.refresh()
        await store.loadCollections()
        if store.error == nil && (!search.isEmpty || hasFilters) { await store.loadSearchPages() }
    }

    private var content: some View {
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing, error: store.error,
            isEmpty: store.items.isEmpty && (!isMainBox || !store.didLoad || store.error != nil),
            emptyIcon: "archivebox",
            emptyTitle: String(localized: "Your Box is empty"),
            emptyDetail: String(localized: "Shared links, text and media appear here."),
            loadingTitle: String(localized: "Loading Box…"),
            hasLoaded: store.didLoad && (store.error == nil || !store.items.isEmpty),
            onRetry: { await store.refresh() }
        ) { browser }
        .closesOnRouteTakeover {
            adding = false
            openedMedia = nil
            collectionItem = nil
            shareItem = nil
            pendingDelete = nil
        }
        .fullScreenCover(item: $openedMedia) { selection in
            BoxMediaDetail(item: selection.item, items: selection.items, store: store, media: media)
        }
        .sheet(item: $collectionItem) { BoxCollectionSheet(original: $0, store: store) }
        .sheet(item: $shareItem) { item in BoxShareDestination(item: item, media: media) }
        .navigationDestination(isPresented: Binding(
            get: { openedDetail != nil }, set: { if !$0 { openedDetail = nil } }
        )) {
            if let openedDetail { BoxDetail(original: openedDetail, store: store, media: media) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await media.retryFailedLoads() } }
        }
    }

    private var browser: some View {
        VStack(spacing: Space.xxs) {
            BoxFilterChips(selection: $filter, author: $author, liked: $liked)
            BoxOrganizationError(store: store)
            BoxResultsView(items: matches) {
                if isMainBox { BoxCollectionStrip(store: store, media: media) }
                if matches.isEmpty && !store.isLoadingMore { emptyResults }
            } row: { item in
                tile(item)
            } footer: {
                pagination
            }
        }
    }

    @ViewBuilder private var emptyResults: some View {
        if hasFilters || !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView("Your Box is empty", systemImage: "archivebox",
                                   description: Text("Shared links, text and media appear here."))
        }
    }

    private func tile(_ item: BoxItem) -> some View {
        BoxTile(item: item, media: media)
            .onTapGesture { open(item) }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(item) }
            .accessibilityIdentifier("box-item-\(item.id)")
            .contextMenu {
                if onSelect == nil {
                    BoxLikeButton(item: item, store: store)
                    Button("Share", systemImage: "square.and.arrow.up") { shareItem = item }
                    Button("Add to Collection…", systemImage: "rectangle.stack") {
                        collectionItem = item
                    }
                    Button("Delete", role: .destructive) { pendingDelete = item }
                        .disabled(store.deleting.contains(item.id))
                }
            }
            .overlay {
                if store.deleting.contains(item.id) {
                    PendingStateView(title: String(localized: "Deleting item…"),
                                     onSettings: openSettings).background(.regularMaterial)
                }
            }
    }

    private var matches: [BoxItem] {
        store.items.filter { filter.matches($0, search: search, author: author, liked: liked) &&
            (store.collectionID == nil || $0.collectionIDs.contains(store.collectionID ?? "")) }
    }

    private func open(_ item: BoxItem) {
        if let onSelect { onSelect(item) }
        else if item.kind == .image || item.kind == .video {
            openedMedia = BoxMediaSelection(item: item, items: matches)
        } else { openedDetail = item }
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
                .frame(minHeight: ControlMetric.minTap).accessibilityIdentifier("box-load-more")
        }
    }
}

struct BoxMediaSelection: Identifiable {
    let item: BoxItem
    let items: [BoxItem]
    var id: String { item.id }
}
