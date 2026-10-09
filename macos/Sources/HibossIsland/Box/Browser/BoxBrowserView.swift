// History window's native Box list with search, kind filtering and confirmed actions.
// Exports: BoxBrowserView; media opens with the system's default application.
// Dependencies: SwiftUI, AppKit, BoxBrowserStore and BoxBrowserMedia.

import AppKit
import HibossKit
import SwiftUI

struct BoxBrowserView: View {
    @ObservedObject var store: BoxBrowserStore
    @ObservedObject var media: BoxBrowserMedia
    @State private var pendingDelete: BoxItem?
    @State private var opening: Set<String> = []
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error, !store.items.isEmpty { errorNotice(error, paging: false) }
            content
        }
        .navigationTitle(L("Box"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .searchable(text: $store.query, placement: .toolbar, prompt: L("Search Box"))
        .toolbar { kindToolbar }
        .task(id: store.query) {
            if !store.query.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            await store.refresh()
        }
        .onChange(of: store.kind) { Task { await store.refresh() } }
        .confirmationDialog(L("Delete this Box item?"), isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            if let item = pendingDelete {
                Button(L("Delete"), role: .destructive) {
                    Task { if await store.delete(item) { media.remove(id: item.id) } }
                    pendingDelete = nil
                }
            }
            Button(L("Cancel"), role: .cancel) { pendingDelete = nil }
        } message: { Text(L("The item will be removed from your Box.")) }
        .alert(L("Box action failed"), isPresented: Binding(
            get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } }
        )) { Button(L("OK"), role: .cancel) { store.actionError = nil } }
        message: { Text(verbatim: store.actionError ?? "") }
    }

    @ToolbarContentBuilder private var kindToolbar: some ToolbarContent {
        ToolbarItem {
            Picker(L("Kind"), selection: $store.kind) {
                Text(L("All kinds")).tag(BoxItem.Kind?.none)
                ForEach(BoxItem.Kind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
            .accessibilityIdentifier("box.kind")
        }
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty, store.isLoading || !store.didLoad {
            ProgressView(L("Loading Box…")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty, let error = store.error {
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
        List {
            if store.isLoading { ProgressView(L("Loading Box…")) }
            ForEach(store.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    BoxBrowserRow(item: item, media: media)
                    HStack {
                        Button(item.kind == .text && !item.hasMedia ? L("Copy text") : L("Open")) {
                            Task { await open(item) }
                        }.disabled(opening.contains(item.id))
                        if opening.contains(item.id) { ProgressView().controlSize(.small) }
                        if copied == item.id { Text(L("Copied")).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button(L("Delete"), role: .destructive) { pendingDelete = item }
                            .disabled(store.deleting.contains(item.id))
                        if store.deleting.contains(item.id) { ProgressView().controlSize(.small) }
                    }.buttonStyle(.borderless)
                }
                .contextMenu {
                    Button(L("Open")) { Task { await open(item) } }
                    if let text = item.text { Button(L("Copy text")) { copy(text, id: item.id) } }
                    Button(L("Delete"), role: .destructive) { pendingDelete = item }
                }
            }
            if store.isPaging { ProgressView(L("Loading more Box items…")) }
            else if let error = store.pageError { errorNotice(error, paging: true) }
            else if store.nextCursor != nil {
                Button(L("Load more")) { Task { await store.loadMore() } }
                    .accessibilityIdentifier("box.load-more")
            }
        }
        .accessibilityIdentifier("box.list")
    }

    private func errorNotice(_ error: String, paging: Bool) -> some View {
        HStack {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button(L("Retry")) {
                Task { if paging { await store.loadMore() } else { await store.refresh() } }
            }
        }.padding(8)
    }

    private func open(_ item: BoxItem) async {
        guard !opening.contains(item.id) else { return }
        opening.insert(item.id)
        defer { opening.remove(item.id) }
        do {
            if let text = try await BoxBrowserActions.open(item, media: media) { copy(text, id: item.id) }
        } catch { store.actionError = error.localizedDescription }
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
