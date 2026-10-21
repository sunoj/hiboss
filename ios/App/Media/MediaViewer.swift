// Shared full-screen media with paging, image zoom, captions and system sharing.
// Exports MediaViewer and optional MediaItemActions for all iOS media entry points.
// Dependencies: SwiftUI, MediaItem, MediaZoomView and the existing looping player.

import SwiftUI

struct MediaItemActions {
    let metadata: (MediaItem) -> String
    let copy: (MediaItem) -> Void
    let info: (MediaItem) -> Void
    let delete: (MediaItem) -> Void
    var likeContent: ((MediaItem) -> AnyView)? = nil
    var errorContent: (() -> AnyView)? = nil
    var isAvailable: (MediaItem) -> Bool = { _ in true }
    var unavailableContent: ((MediaItem) -> AnyView?)? = nil
}

struct MediaViewer: View {
    let items: [MediaItem]
    let itemActions: MediaItemActions?
    let onSelection: ((String) async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var currentID: String?
    @State private var offset: CGFloat = 0
    @State private var zoomed = false
    @State private var unmuted = false
    @State private var chromeVisible = true
    @StateObject private var sharing = MediaShareStore()

    init(items: [MediaItem], startIndex: Int, itemActions: MediaItemActions? = nil,
         onSelection: ((String) async -> Void)? = nil) {
        self.items = items
        self.itemActions = itemActions
        self.onSelection = onSelection
        _currentID = State(initialValue: items.indices.contains(startIndex) ? items[startIndex].id : nil)
    }

    var body: some View {
        ZStack {
            Theme.mediaBackground.ignoresSafeArea()
            pager
                .offset(y: offset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { if chromeVisible && itemActions == nil { topBar } }
        .overlay(alignment: .bottom) { if chromeVisible && itemActions == nil { captionArea } }
        .safeAreaInset(edge: .top, spacing: 0) {
            if chromeVisible && itemActions != nil { topBar }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if chromeVisible && itemActions != nil { captionArea }
        }
        .accessibilityAddTraits(.isModal)
        .task(id: currentID) {
            if let currentID { await onSelection?(currentID) }
        }
        .onChange(of: currentID) { _, _ in
            zoomed = false
            offset = 0
            unmuted = false
        }
        .sheet(item: $sharing.resource) { resource in
            MediaShareSheet(url: resource.url)
        }
        .onDisappear { sharing.cancel() }
    }

    private var pager: some View {
        GeometryReader { geo in
            TabView(selection: $currentID) {
                ForEach(items) { item in
                    page(item, size: geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .tag(Optional(item.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(zoomed)
        }
        .ignoresSafeArea(edges: itemActions == nil ? .all : [])
    }

    @ViewBuilder
    private func page(_ item: MediaItem, size: CGSize) -> some View {
        MediaZoomView(
            pageID: item.id,
            allowsZoom: true,
            onZoomed: { if currentID == item.id { zoomed = $0 } },
            onDismissDrag: { offset = $0 },
            onDismiss: { dismiss() },
            onSingleTap: { chromeVisible.toggle() }
        ) {
            pageContent(item)
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func pageContent(_ item: MediaItem) -> some View {
        if let unavailable = itemActions?.unavailableContent?(item) { unavailable }
        else { loadedContent(item) }
    }

    @ViewBuilder
    private func loadedContent(_ item: MediaItem) -> some View {
        switch item.kind {
        case .image:
            RemoteImage(url: item.url, retryIdentifier: "media-viewer-image-retry") { image in
                image.resizable().scaledToFit()
                    .accessibilityLabel(Text(verbatim: item.title ?? String(localized: "Image")))
                    .accessibilityIdentifier("media-viewer-image")
            }
        case .video:
            videoPage(item)
        }
    }

    @ViewBuilder
    private func videoPage(_ item: MediaItem) -> some View {
        if itemActions != nil {
            MediaSystemVideo(url: item.url, isPlaying: currentID == item.id)
                .aspectRatio(item.aspectRatio, contentMode: .fit)
                .accessibilityIdentifier("media-viewer-video")
        } else {
            LoopingPlayerView(
                url: item.url,
                isMuted: !unmuted,
                isPlaying: currentID == item.id,
                fill: false
            )
            .aspectRatio(item.aspectRatio, contentMode: .fit)
            .accessibilityLabel(Text(verbatim: item.title ?? String(localized: "Video")))
            .accessibilityIdentifier("media-viewer-video")
        }
    }

    @ViewBuilder
    private func muteControl(for item: MediaItem) -> some View {
        if item.kind == .video && itemActions == nil {
            Button { unmuted.toggle() } label: {
                Image(systemName: unmuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unmuted ? String(localized: "Mute") : String(localized: "Unmute"))
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier("media-viewer-close")
    }

    private var selectedItem: MediaItem? { items.first { $0.id == currentID } }

    private var topBar: some View {
        HStack {
            closeButton
            Spacer()
            if items.count > 1 || itemActions != nil,
               let index = items.firstIndex(where: { $0.id == currentID }) {
                Text(verbatim: "\(index + 1) / \(items.count)").font(.headline).monospacedDigit()
                    .accessibilityIdentifier("media-viewer-counter")
            }
            Spacer()
            Button {
                if let selectedItem { sharing.share(selectedItem) }
            } label: {
                Image(systemName: "square.and.arrow.up").font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(sharing.isLoading || selectedItem == nil ||
                      selectedItem.map { itemActions?.isAvailable($0) == false } == true)
            .accessibilityLabel("Share")
            .accessibilityIdentifier("media-viewer-share")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var captionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = selectedItem {
                muteControl(for: item)
                if item.title != nil || item.caption != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if let title = item.title { Text(verbatim: title).font(.headline) }
                            if let caption = item.caption { Text(verbatim: caption).font(.body) }
                            if let itemActions {
                                TimelineView(.everyMinute) { _ in
                                    Text(verbatim: itemActions.metadata(item)).font(.caption)
                                        .foregroundStyle(Theme.ink2)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160)
                        .accessibilityIdentifier("media-viewer-caption")
                }
                if let itemActions {
                    actionBar(item, actions: itemActions)
                    itemActions.errorContent?()
                }
            }
            if sharing.isLoading {
                PendingStateView(title: String(localized: "Preparing media…"),
                                 onRetry: { if let selectedItem { sharing.share(selectedItem) } })
            }
            if let error = sharing.error {
                Text(verbatim: error).font(.callout)
                Button("Retry") { if let selectedItem { sharing.share(selectedItem) } }
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func actionBar(_ item: MediaItem, actions: MediaItemActions) -> some View {
        if textSize.isAccessibilitySize {
            actionButtons(item, actions: actions).labelStyle(.iconOnly)
        } else { actionButtons(item, actions: actions) }
    }

    private func actionButtons(_ item: MediaItem, actions: MediaItemActions) -> some View {
        HStack {
            if let like = actions.likeContent {
                like(item).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            Button("Copy", systemImage: "doc.on.doc") { actions.copy(item) }
                .disabled(!actions.isAvailable(item))
                .accessibilityIdentifier("media-viewer-copy")
            Spacer()
            Button("Info", systemImage: "info.circle") { actions.info(item) }
                .accessibilityIdentifier("media-viewer-info")
            Spacer()
            Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(item) }
                .accessibilityIdentifier("media-viewer-delete")
        }.buttonStyle(.bordered).controlSize(.large)
    }
}
