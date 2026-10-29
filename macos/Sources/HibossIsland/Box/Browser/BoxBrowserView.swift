// Native Box list with search, kind filtering, confirmed actions and nested image previews.
// Exports: BoxBrowserView; images preview in-app and other media opens with the default application.
// Dependencies: SwiftUI, AppKit, BoxBrowserStore and BoxBrowserMedia.

import AppKit
import HibossKit
import QuickLook
import SwiftUI

struct BoxBrowserView: View {
    @ObservedObject var store: BoxBrowserStore
    @ObservedObject var media: BoxBrowserMedia
    var sidebar: AnyView? = nil
    @State var opening: Set<String> = []
    @State var copied: String?
    @State var previewImage: BoxItem?
    @State var quickLookURL: URL?
    @State var editingNote: BoxItem?

    var body: some View {
        browser
        .navigationTitle(L("Box"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspaceChrome()
        .task(id: store.query) {
            if !store.query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await store.refresh()
        }
        .onChange(of: store.scope) { Task { await store.refresh() } }
        .onChange(of: store.kind) { Task { await store.refresh() } }
        .onChange(of: store.project) { Task { await store.refresh() } }
        .sheet(isPresented: $store.creatingCollection) {
            BoxCollectionEditor(store: store, item: store.newCollectionItem)
        }
        .sheet(item: $editingNote) { item in BoxNoteEditor(item: item, store: store) }
        .quickLookPreview($quickLookURL)
        .alert(store.pendingDelete?.deleteTitle ?? L("Delete this Box item?"),
            isPresented: Binding(get: { store.pendingDelete != nil },
                set: { if !$0, store.pendingDelete != nil { store.pendingDelete = nil } }),
            presenting: store.pendingDelete) { item in
            Button(L("Delete"), role: .destructive) {
                Task { if let deleted = await store.confirmDelete(item) { media.remove(id: deleted.id) } }
            }
            Button(L("Cancel"), role: .cancel) { store.pendingDelete = nil }
                .keyboardShortcut(.defaultAction)
        } message: { _ in Text(L("Agents will no longer be able to read this item.")) }
        .alert(L("Box action failed"), isPresented: Binding(
            get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } }
        )) { Button(L("OK"), role: .cancel) { store.actionError = nil } }
        message: { Text(verbatim: store.actionError ?? "") }
    }

    @ToolbarContentBuilder private var filters: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            BoxBrowserFilters(store: store)
            BoxBrowserFilters(store: store).authorPicker
            BoxBrowserFilters(store: store).projectPicker
        }
    }

    private var browser: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 900 {
                BoxBrowserColumns(
                    sidebar: sidebar,
                    content: listColumn, detail: detailColumn)
                    .toolbar { filters }
                    .searchable(text: $store.query, placement: .toolbar, prompt: L("Search Box"))
            } else {
                NavigationStack {
                    listColumn
                        .sheet(isPresented: Binding(get: { store.selectedItem != nil },
                            set: { if !$0 { store.selection = nil } })) {
                            VStack(spacing: 0) {
                                HStack {
                                    Spacer()
                                    Button(L("Done")) { store.selection = nil }
                                }.padding(12)
                                detailColumn
                            }.frame(minWidth: 320, idealWidth: 420, minHeight: 400)
                        }
                        .searchable(text: $store.query, placement: .toolbar, prompt: L("Search Box"))
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Menu {
                                    BoxBrowserFilters(store: store)
                                    BoxBrowserFilters(store: store).authorPicker
                                    BoxBrowserFilters(store: store).projectPicker
                                } label: { Label(L("Filter"), systemImage: "line.3.horizontal.decrease") }
                                .labelStyle(.iconOnly)
                                .layoutProbe("box.compact-filters")
                            }
                        }
                }
            }
        }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                Text(L("Box items: \(store.visibleItems.count)"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .layoutProbe("box.item-count")
                Spacer(minLength: 0)
                CachedReadStatus(isRefreshing: store.hasResult && store.isLoading,
                    failure: store.hasResult ? store.error : nil,
                    retry: { Task { await store.refresh() } })
                    .fixedSize(horizontal: true, vertical: false)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 28)
                .padding(.horizontal, 8)
                .layoutProbe("box.read-status")
        }
        .workspaceChrome()
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            BoxBrowserDetail(item: store.selectedItem, media: media,
                busy: store.selectedItem.map { opening.contains($0.id) || store.deleting.contains($0.id) }
                    ?? false,
                copied: copied != nil && copied == store.selection, store: store) { action in
                    if let item = store.selectedItem { perform(action, item: item) }
                }
                .workspaceChrome()
                .frame(minWidth: 280, idealWidth: 400, maxWidth: .infinity)
                .sheet(item: $previewImage) { item in
                    BoxImagePreview(item: item, media: media)
                }
        }
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty, !store.didLoad {
            ProgressView(L("Loading Box…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty, !store.hasResult, let error = store.error {
            ContentUnavailableView {
                Label(L("Box Unavailable"), systemImage: "exclamationmark.triangle")
            } description: { Text(verbatim: error) }
            actions: { Button(L("Retry")) { Task { await store.refresh() } } }
        } else if store.items.isEmpty {
            ContentUnavailableView(L("Your Box is empty"), systemImage: "archivebox",
                description: Text(store.kind != nil || !store.query.isEmpty
                    ? L("Try a different filter or search.")
                    : L("Shared links, text and media appear here.")))
        } else { list }
    }

    private var list: some View {
        BoxBrowserList(store: store, media: media, busy: opening.union(store.deleting),
            onOpenImage: { item in
                store.selection = item.id
                previewImage = item
            }, onPerform: { perform($0, item: $1) })
            .equatable()
    }
}

extension BoxItem.Kind {
    var title: String {
        switch self {
        case .link: L("Link")
        case .text: L("Text")
        case .image: L("Image")
        case .video: L("Video")
        case .file: L("File")
        }
    }
}
