// Box browser with remembered list/cards styles, combined filters and confirmed row actions.
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
    @AppStorage("box-list-style") private var style = BoxListStyle.list
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
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing, error: store.error,
            isEmpty: store.items.isEmpty, emptyIcon: "archivebox",
            emptyTitle: String(localized: "Your Box is empty"),
            emptyDetail: String(localized: "Shared links, text and media appear here."),
            loadingTitle: String(localized: "Loading Box…"), hasLoaded: store.didLoad,
            onRetry: { await store.refresh() }
        ) { list }
        .background(Theme.paper)
        .toolbarTitleDisplayMode(onSelect == nil ? .inlineLarge : .automatic)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search notes, links and files")
        .task {
            if !store.didLoad { await store.refresh() }
            await store.loadCollections()
            if !search.isEmpty || filter != .all { await store.loadSearchPages() }
        }
        .task(id: search + filter.rawValue + author.rawValue + String(liked)) {
            if !search.isEmpty || filter != .all || author != .all || liked { await store.loadSearchPages() }
        }
        .refreshable {
            await store.refresh()
            await store.loadCollections()
            if !search.isEmpty || filter != .all || author != .all || liked { await store.loadSearchPages() }
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
        .modifier(BoxDeleteConfirmation(item: $pendingDelete, store: store, media: media))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await media.retryFailedLoads() } }
        }
        .toolbar { controls }
    }

    private var list: some View {
        VStack(spacing: 0) {
            BoxFilterChips(selection: $filter, liked: $liked)
            BoxOrganizationError(store: store)
            if matches.isEmpty && !store.isLoadingMore { ContentUnavailableView.search(text: search) }
            BoxResultsView(items: matches, filter: filter, style: style, row: { item in
                actionableRow(item)
                    .contextMenu {
                        if onSelect == nil {
                            BoxLikeButton(item: item, store: store)
                            Button("Share", systemImage: "square.and.arrow.up") { share(item) }
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
            }, footer: { pagination })
        }
    }

    private var matches: [BoxItem] {
        store.items.filter { filter.matches($0, search: search, author: author, liked: liked) &&
            (store.collectionID == nil || $0.collectionIDs.contains(store.collectionID ?? "")) }
    }

    @ViewBuilder private func actionableRow(_ item: BoxItem) -> some View {
        if onSelect == nil && style == .list && !filter.isMedia {
            row(item)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) { pendingDelete = item }
                        .disabled(store.deleting.contains(item.id))
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    BoxLikeButton(item: item, store: store)
                    Button("Share", systemImage: "square.and.arrow.up") { share(item) }
                }
        } else {
            row(item)
        }
    }

    private func share(_ item: BoxItem) {
        shareItem = item
    }

    @ViewBuilder private func row(_ item: BoxItem) -> some View {
        if style == .cards || filter.isMedia {
            rowLabel(item)
                .contentShape(Rectangle())
                .onTapGesture { open(item) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("box-item-\(item.id)")
        } else {
            Button { open(item) } label: { rowLabel(item) }
                .buttonStyle(.plain).contentShape(Rectangle())
                .accessibilityIdentifier("box-item-\(item.id)")
        }
    }

    private func open(_ item: BoxItem) {
        if let onSelect { onSelect(item) }
        else if item.kind == .image || item.kind == .video {
            openedMedia = BoxMediaSelection(item: item, items: matches)
        } else { openedDetail = item }
    }

    @ViewBuilder private func rowLabel(_ item: BoxItem) -> some View {
        if filter.isMedia {
            BoxThumbnail(item: item, media: media).aspectRatio(1, contentMode: .fit)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: item.boxTitle + " · " + item.metadata))
        } else { BoxRow(item: item, media: media, grid: style == .cards) }
    }

    @ToolbarContentBuilder private var controls: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if onSelect == nil && store.collectionID == nil {
                NavigationLink {
                    BoxCollectionsView(store: store, media: media)
                } label: { Image(systemName: "rectangle.stack") }
                .accessibilityLabel("Collections")
                .accessibilityIdentifier("box-collections")
            }
            Menu {
                Picker("Author", selection: $author) {
                    ForEach(BoxAuthorFilter.allCases, id: \.self) { option in
                        Text(verbatim: option.title).tag(option)
                            .accessibilityIdentifier("box-author-\(option.rawValue)")
                    }
                }
            } label: { Image(systemName: "person.crop.circle") }
                .accessibilityLabel("Author")
                .accessibilityValue(Text(verbatim: author.title))
                .accessibilityIdentifier("box-author-menu")
            Menu {
                Picker("List style", selection: $style) {
                    ForEach(BoxListStyle.allCases, id: \.self) { option in
                        Text(verbatim: option.title).tag(option)
                            .accessibilityIdentifier("box-style-\(option.rawValue)")
                    }
                }
            } label: {
                Image(systemName: style == .list ? "list.bullet" : "square.grid.2x2")
            }
                .accessibilityLabel("List style")
                .accessibilityValue(Text(verbatim: style.title))
                .accessibilityIdentifier("box-style-menu")
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

struct BoxMediaSelection: Identifiable {
    let item: BoxItem
    let items: [BoxItem]
    var id: String { item.id }
}
