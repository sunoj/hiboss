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
    @State private var opening: Set<String> = []
    @State private var copied: String?
    @State private var previewImage: BoxItem?
    @State private var quickLookURL: URL?
    @State private var editingNote: BoxItem?

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
        .onChange(of: store.kind) { Task { await store.refresh() } }
        .onChange(of: store.project) { Task { await store.refresh() } }
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
        ToolbarItem(placement: .automatic) { BoxBrowserFilters(store: store) }
        ToolbarItem(placement: .automatic) { BoxBrowserFilters(store: store).authorPicker }
        ToolbarItem(placement: .automatic) { BoxBrowserFilters(store: store).projectPicker }
    }

    private var browser: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 900 {
                BoxBrowserColumns(sidebar: sidebar, content: listColumn, detail: detailColumn)
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
        BoxBrowserDetail(item: store.selectedItem, media: media,
            busy: store.selectedItem.map { opening.contains($0.id) || store.deleting.contains($0.id) }
                ?? false,
            copied: copied != nil && copied == store.selection) { action in
                if let item = store.selectedItem { perform(action, item: item) }
            }
            .workspaceChrome()
            .frame(minWidth: 280, idealWidth: 400, maxWidth: .infinity)
            .sheet(item: $previewImage) { item in
                BoxImagePreview(item: item, media: media)
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
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            List(selection: $store.selection) {
                if store.visibleItems.isEmpty {
                    Text(L("No Matching Items")).foregroundStyle(.secondary)
                }
                ForEach(BoxDateSection.allCases) { section in
                    let items = store.visibleItems.filter {
                        BoxDateSection.section(for: $0.createdAt, now: tick.date) == section
                    }
                    if !items.isEmpty {
                        Section(section.title) {
                            ForEach(items) { item in
                                row(item)
                            }
                        }
                    }
                }
                if store.isPaging { ProgressView(L("Loading more Box items…")) }
                else if let error = store.pageError { errorNotice(error) }
                else if store.nextCursor != nil {
                    Button(L("Load more")) { Task { await store.loadMore() } }
                        .accessibilityIdentifier("box.load-more")
                }
            }
            .accessibilityIdentifier("box.list")
            .layoutProbe("box.list")
            .onKeyPress(.space) {
                guard let item = store.selectedItem else { return .ignored }
                perform(.quickLook, item: item)
                return .handled
            }
            .onKeyPress(.upArrow) { store.moveSelection(by: -1); return .handled }
            .onKeyPress(.downArrow) { store.moveSelection(by: 1); return .handled }
            .onDeleteCommand {
                if let item = store.selectedItem { store.requestDelete(item) }
            }
        }
    }

    private func row(_ item: BoxItem) -> some View {
        BoxBrowserRow(item: item, media: media) {
            store.selection = item.id
            previewImage = item
        }
            .tag(item.id)
            .contentShape(Rectangle())
            .contextMenu {
                BoxPaneActions(item: item,
                    busy: opening.contains(item.id) || store.deleting.contains(item.id)) {
                        perform($0, item: item)
                    }
            }
    }

    private func errorNotice(_ error: String) -> some View {
        HStack {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button(L("Retry")) {
                Task { await store.loadMore() }
            }
        }.padding(8)
    }

    private func open(_ item: BoxItem) async {
        if item.hasImageMedia {
            store.selection = item.id
            previewImage = item
            return
        }
        guard !opening.contains(item.id) else { return }
        opening.insert(item.id)
        defer { opening.remove(item.id) }
        do {
            if let text = try await BoxBrowserActions.open(item, media: media) { copy(text, id: item.id) }
        } catch { store.actionError = error.localizedDescription }
    }

    private func perform(_ action: BoxPaneAction, item: BoxItem) {
        if action == .delete {
            store.requestDelete(item)
            return
        }
        if action == .editNote {
            editingNote = item
            return
        }
        if action == .open {
            Task { await open(item) }
            return
        }
        Task {
            guard !opening.contains(item.id) else { return }
            opening.insert(item.id)
            defer { opening.remove(item.id) }
            do {
                switch action {
                case .quickLook: quickLookURL = try await BoxBrowserActions.previewURL(item, media: media)
                case .copy:
                    try await BoxBrowserActions.copy(item, media: media)
                    copied = item.id
                case .share: try await BoxBrowserActions.share(item, media: media)
                default: break
                }
            } catch { store.actionError = error.localizedDescription }
        }
    }

    private func copy(_ text: String, id: String) {
        if BoxBrowserActions.copy(text) { copied = id }
        else { store.actionError = BoxBrowserError.cannotOpen.localizedDescription }
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
