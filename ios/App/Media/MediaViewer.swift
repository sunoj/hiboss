// Shared full-screen media with paging, image zoom, captions and system sharing.
// Exports MediaViewer for all iOS image and video entry points.
// Dependencies: SwiftUI, MediaItem, MediaZoomView and the existing looping player.

import SwiftUI

struct MediaViewer: View {
    let items: [MediaItem]

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String?
    @State private var offset: CGFloat = 0
    @State private var zoomed = false
    @State private var unmuted = false
    @State private var chromeVisible = true
    @StateObject private var sharing = MediaShareStore()

    init(items: [MediaItem], startIndex: Int) {
        self.items = items
        _currentID = State(initialValue: items.indices.contains(startIndex) ? items[startIndex].id : nil)
    }

    var body: some View {
        ZStack {
            Theme.mediaBackground.ignoresSafeArea()
            pager
                .offset(y: offset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { if chromeVisible { topBar } }
        .overlay(alignment: .bottom) { if chromeVisible { captionArea } }
        .accessibilityAddTraits(.isModal)
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
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        page(item, size: geo.size)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollDisabled(zoomed)
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func page(_ item: MediaItem, size: CGSize) -> some View {
        MediaZoomView(
            pageID: item.id,
            allowsZoom: item.kind == .image,
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
        LoopingPlayerView(
            url: item.url,
            isMuted: !unmuted,
            isPlaying: currentID == item.id,
            fill: false
        )
        .aspectRatio(
            item.aspectRatio,
            contentMode: .fit
        )
        .accessibilityLabel(Text(verbatim: item.title ?? String(localized: "Video")))
        .accessibilityIdentifier("media-viewer-video")
    }

    @ViewBuilder
    private func muteControl(for item: MediaItem) -> some View {
        if item.kind == .video {
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
            if items.count > 1, let index = items.firstIndex(where: { $0.id == currentID }) {
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
            .disabled(sharing.isLoading || selectedItem == nil)
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
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160)
                        .accessibilityIdentifier("media-viewer-caption")
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
}
