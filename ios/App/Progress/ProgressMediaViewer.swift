// Full-screen progress media: paging, pinch zoom, swipe down to dismiss.
// Exports: ProgressMediaSession, ProgressMediaViewer.
// Dependencies: SwiftUI, HibossKit ProgressMedia, ProgressZoomView.

import HibossKit
import SwiftUI

struct ProgressMediaSession: Identifiable {
    let items: [ProgressMedia]
    let index: Int
    var id: String { items[index].url }
}

struct ProgressMediaViewer: View {
    let items: [ProgressMedia]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String?
    @State private var offset: CGFloat = 0
    @State private var zoomed = false
    @State private var unmuted = false

    init(items: [ProgressMedia], startIndex: Int) {
        self.items = items
        self.startIndex = startIndex
        _currentID = State(initialValue: items[startIndex].url)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            pager
                .offset(y: offset)
        }
        .modifier(SwipeDownDismiss(enabled: !zoomed, offset: $offset, dismiss: { dismiss() }))
        .overlay(alignment: .topLeading) { closeButton }
        .accessibilityAddTraits(.isModal)
    }

    private var pager: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        page(item, size: geo.size)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(item.url)
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
    private func page(_ item: ProgressMedia, size: CGSize) -> some View {
        ProgressZoomView(pageID: item.url, onZoomed: { zoomed = $0 }) {
            pageContent(item)
                .frame(width: size.width, height: size.height)
        }
        .overlay(alignment: .bottomLeading) { muteControl(for: item) }
    }

    @ViewBuilder
    private func pageContent(_ item: ProgressMedia) -> some View {
        switch item.kind {
        case .image:
            AsyncImage(url: URL(string: item.url)) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit()
                case .failure:
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .accessibilityLabel(item.alt ?? String(localized: "Image"))
        case .video:
            videoPage(item)
        }
    }

    @ViewBuilder
    private func videoPage(_ item: ProgressMedia) -> some View {
        if let url = URL(string: item.url) {
            LoopingPlayerView(
                url: url,
                isMuted: !unmuted,
                isPlaying: currentID == item.url,
                fill: false
            )
            .aspectRatio(
                ProgressMediaLayout.clampedAspect(width: item.width, height: item.height),
                contentMode: .fit
            )
            .accessibilityLabel(item.alt ?? String(localized: "Video"))
        }
    }

    @ViewBuilder
    private func muteControl(for item: ProgressMedia) -> some View {
        if item.kind == .video, currentID == item.url {
            Button { unmuted.toggle() } label: {
                Image(systemName: unmuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.body)
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding()
            .accessibilityLabel(unmuted ? String(localized: "Mute") : String(localized: "Unmute"))
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .padding()
        .accessibilityLabel("Close")
    }
}

private struct SwipeDownDismiss: ViewModifier {
    let enabled: Bool
    @Binding var offset: CGFloat
    var dismiss: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(drag)
        } else {
            content
        }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation.height }
            .onEnded { value in
                if value.translation.height > 120 { dismiss() } else { offset = 0 }
            }
    }
}
