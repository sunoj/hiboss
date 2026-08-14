// Media strip for a progress post: AsyncImage plus a full-screen viewer.
// Exports: ProgressMediaView, ProgressMediaViewer, ProgressImageCell.
// Dependencies: SwiftUI, HibossKit ProgressMedia, ProgressVideoCell.

import HibossKit
import SwiftUI

struct ProgressMediaView: View {
    let items: [ProgressMedia]
    var onOpen: (ProgressMedia) -> Void

    var body: some View {
        if items.count == 1, let item = items.first {
            cell(item)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)],
                spacing: 4
            ) {
                ForEach(items) { cell($0) }
            }
        }
    }

    @ViewBuilder
    private func cell(_ item: ProgressMedia) -> some View {
        switch item.kind {
        case .image:
            ProgressImageCell(media: item)
                .onTapGesture { onOpen(item) }
        case .video:
            ProgressVideoCell(media: item, onExpand: { onOpen(item) })
        }
    }
}

struct ProgressImageCell: View {
    let media: ProgressMedia

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(media.aspectRatio, contentMode: .fit)
            .overlay { imageOverlay }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(media.alt ?? "Image")
    }

    @ViewBuilder
    private var imageOverlay: some View {
        AsyncImage(url: URL(string: media.url)) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
            default:
                ProgressView()
            }
        }
    }
}

struct ProgressMediaViewer: View {
    let media: ProgressMedia
    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var unmuted = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
                .offset(y: offset)
        }
        .gesture(drag)
        .overlay(alignment: .topLeading) { closeButton }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var content: some View {
        switch media.kind {
        case .image:
            AsyncImage(url: URL(string: media.url)) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFit()
                case .failure:
                    Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
        case .video:
            if let url = URL(string: media.url) {
                LoopingPlayerView(url: url, isMuted: !unmuted, isPlaying: true, fill: false)
                    .aspectRatio(media.aspectRatio, contentMode: .fit)
                    .onTapGesture { unmuted.toggle() }
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: unmuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.body)
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                            .padding()
                            .allowsHitTesting(false)
                    }
            }
        }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation.height }
            .onEnded { value in
                if abs(value.translation.height) > 120 { dismiss() } else { offset = 0 }
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

extension ProgressMedia {
    /// Reserve layout using probed dimensions; 16:9 when the CLI omitted them.
    var aspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 16 / 9 }
        return CGFloat(width) / CGFloat(height)
    }
}
