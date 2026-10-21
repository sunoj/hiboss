// Box filtered media sessions with optional copy, information and confirmed delete actions.
// Exports BoxMediaDetail, retaining authenticated resources while the shared viewer is open.
// Dependencies: SwiftUI, HibossKit, MediaViewer and BoxDetail.

import HibossKit
import SwiftUI

struct BoxMediaDetail: View {
    let item: BoxItem
    let items: [BoxItem]
    @ObservedObject var store: BoxStore
    @ObservedObject var media: BoxMediaStore
    @Environment(\.dismiss) private var dismiss
    @State private var info: BoxItem?
    @State private var pendingDelete: BoxItem?

    var body: some View {
        MediaViewer(items: pages, startIndex: candidates.firstIndex { $0.id == item.id } ?? 0,
                    itemActions: actions,
                    onSelection: { await media.loadSelection(id: $0, items: candidates) })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("box-media-detail")
        .sheet(item: $info) { selected in
            NavigationStack {
                BoxDetail(original: selected, store: store, media: media)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { info = nil } } }
            }
        }
        .onChange(of: store.items) { _, updated in
            if mapping.values.contains(where: { target in !updated.contains { $0.id == target.id } }) {
                dismiss()
            }
        }
        .modifier(BoxDeleteConfirmation(item: $pendingDelete, store: store, media: media,
                                        onDeleted: { dismiss() }))
    }

    private var actions: MediaItemActions {
        MediaItemActions(
            metadata: { selected in
                guard let target = store.items.first(where: { $0.id == selected.id }) else { return "" }
                return target.authorLabel + " · " + (target.relativeTime ?? "")
            },
            copy: { selected in mapping[selected.id]?.copyContent(media: media) },
            info: { selected in info = mapping[selected.id] },
            delete: { selected in pendingDelete = mapping[selected.id] },
            likeContent: { selected in
                guard let target = store.items.first(where: { $0.id == selected.id }) else {
                    return AnyView(EmptyView())
                }
                return AnyView(BoxLikeButton(item: target, store: store))
            },
            errorContent: { AnyView(BoxOrganizationError(store: store)) },
            isAvailable: { selected in media.resources[selected.id] != nil },
            unavailableContent: { selected in
                guard media.resources[selected.id] == nil,
                      let target = mapping[selected.id] else { return nil }
                return AnyView(BoxMediaWait(item: target, media: media).padding())
            })
    }

    private var candidates: [BoxItem] {
        items.filter { $0.kind == .image || $0.kind == .video }
    }

    private var mapping: [String: BoxItem] {
        Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
    }

    private var pages: [MediaItem] {
        candidates.map { original in
            let target = store.items.first { $0.id == original.id } ?? original
            // Pending pages keep their position; unavailableContent supplies loading/retry UI.
            let url = media.resources[target.id]?.url ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("box-pending-\(target.id)")
            return MediaItem(id: target.id,
                url: url, kind: target.kind == .video ? .video : .image,
                title: target.boxTitle, caption: target.note,
                aspectRatio: ProgressMediaLayout.clampedAspect(width: target.width, height: target.height))
        }
    }
}
