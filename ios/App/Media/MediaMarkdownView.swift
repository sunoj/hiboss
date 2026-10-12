// Adds tappable image galleries to iOS Markdown while retaining native text/table rendering.
// Exports MediaMarkdownView for message bodies, transcripts and document previews.
// Dependencies: SwiftUI, HibossKit Markdown views, RemoteImage and MediaViewer.

import HibossKit
import SwiftUI

struct MediaMarkdownView: View {
    private let segments: [MediaMarkdown.Segment]
    private let document: Bool
    @State private var opened: MediaSession?

    init(_ source: String, document: Bool = false, baseURL: URL? = nil) {
        segments = MediaMarkdown.segments(source, baseURL: baseURL)
        self.document = document
    }

    private var images: [MediaItem] {
        segments.compactMap {
            if case let .image(item) = $0 { return item }
            return nil
        }
    }

    var body: some View {
        if images.isEmpty {
            textOnlyBody
        } else {
            mediaBody
        }
    }

    @ViewBuilder
    private var textOnlyBody: some View {
        if case let .text(source) = segments.first {
            if document { MarkdownDocumentView(source: source) }
            else { MessageMarkdownView(source) }
        }
    }

    private var mediaBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let source):
                    if document { MarkdownDocumentView(source: source) }
                    else { MessageMarkdownView(source) }
                case .image(let item):
                    thumbnail(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .fullScreenCover(item: $opened) { session in
            MediaViewer(items: session.items, startIndex: session.index)
        }
    }

    private func thumbnail(_ item: MediaItem) -> some View {
        Rectangle().fill(Theme.surface2)
            .aspectRatio(1.5, contentMode: .fit)
            .overlay {
                Button {
                    if let index = images.firstIndex(where: { $0.id == item.id }) {
                        opened = MediaSession(items: images, index: index)
                    }
                } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open image for \(item.title ?? String(localized: "Image"))")
                    .accessibilityIdentifier("markdown-media-open")
            }
            .overlay {
                RemoteImage(url: item.url, compact: true) { image in
                    image.resizable().scaledToFit().allowsHitTesting(false)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .textSelection(.disabled)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
