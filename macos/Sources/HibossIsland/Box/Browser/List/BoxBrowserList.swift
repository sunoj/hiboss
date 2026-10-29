// Box list rendering isolated from refresh-status and unrelated browser state publications.
// Exports: BoxBrowserList and its equatable input snapshot; actions retain their owning browser.
// Dependencies: SwiftUI, HibossKit, BoxBrowserStore and BoxBrowserMedia.

import HibossKit
import SwiftUI

struct BoxBrowserList: View, Equatable {
    struct BoxBrowserListSnapshot: Equatable, Sendable {
        let items: [BoxItem]
        let selection: String?
        let isPaging: Bool
        let pageError: String?
        let nextCursor: String?
        let busy: Set<String>
    }

    let store: BoxBrowserStore
    let media: BoxBrowserMedia
    let snapshot: BoxBrowserListSnapshot
    let onOpenImage: (BoxItem) -> Void
    let onPerform: (BoxPaneAction, BoxItem) -> Void

    init(store: BoxBrowserStore, media: BoxBrowserMedia, busy: Set<String>,
         onOpenImage: @escaping (BoxItem) -> Void, onPerform: @escaping (BoxPaneAction, BoxItem) -> Void) {
        self.store = store
        self.media = media
        snapshot = BoxBrowserListSnapshot(items: store.visibleItems, selection: store.selection,
            isPaging: store.isPaging, pageError: store.pageError, nextCursor: store.nextCursor, busy: busy)
        self.onOpenImage = onOpenImage
        self.onPerform = onPerform
    }

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        // Callbacks address the same browser's state; only the owners and list inputs affect rendering.
        lhs.store === rhs.store && lhs.media === rhs.media && lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            let groups = BoxDateSection.grouped(snapshot.items, now: tick.date)
            list(groups: groups)
        }
    }

    private func list(groups: [BoxDateSection: [BoxItem]]) -> some View {
        let sections = BoxDateSection.allCases.filter { groups[$0] != nil }
        return List(selection: Binding(get: { store.selection }, set: { store.selection = $0 })) {
            if snapshot.items.isEmpty {
                Text(L("No Matching Items")).foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(groups[section] ?? []) { item in
                        row(item)
                    }
                }
            }
            if snapshot.isPaging { ProgressView(L("Loading more Box items…")) }
            else if let error = snapshot.pageError { errorNotice(error) }
            else if snapshot.nextCursor != nil {
                Button(L("Load more")) { Task { await store.loadMore() } }
                    .accessibilityIdentifier("box.load-more")
            }
        }
        .accessibilityIdentifier("box.list")
        .layoutProbe("box.list")
        .onKeyPress(.space) {
            guard let item = store.selectedItem else { return .ignored }
            onPerform(.quickLook, item)
            return .handled
        }
        .onKeyPress(keys: ["l"]) { press in
            guard press.modifiers == .command, let item = store.selectedItem else { return .ignored }
            Task { await store.toggleLike(item) }
            return .handled
        }
        .onKeyPress(.upArrow) { store.moveSelection(by: -1); return .handled }
        .onKeyPress(.downArrow) { store.moveSelection(by: 1); return .handled }
        .onDeleteCommand {
            if let item = store.selectedItem { store.requestDelete(item) }
        }
    }

    private func row(_ item: BoxItem) -> some View {
        BoxBrowserRow(item: item, media: media) { onOpenImage(item) }
            .tag(item.id)
            .contentShape(Rectangle())
            .draggable(item.id)
            .contextMenu {
                BoxCollectionActions(store: store, item: item)
                BoxPaneActions(item: item, busy: snapshot.busy.contains(item.id)) {
                    onPerform($0, item)
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
}
