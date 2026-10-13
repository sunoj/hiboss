// Aspect-aware image grids and video posters that open the native large media viewer.
// Exports: ProgressMediaGrid and ProgressRemoteImage with cached loading/retry states.
// Dependencies: SwiftUI, AppKit, ProgressMediaLayout and ProgressImageLoader.

import AppKit
import HibossKit
import SwiftUI

struct ProgressMediaGrid: View {
    let items: [ProgressMedia]
    let onOpen: (ProgressMedia) -> Void

    var body: some View {
        ProgressMediaLayout(items: items) {
            ForEach(items) { media in
                ZStack {
                    Button { onOpen(media) } label: {
                        Color(nsColor: .controlBackgroundColor).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(media.alt ?? (media.kind == .image ? L("Image") : L("Play video")))
                    .accessibilityHint(L("Open large viewer"))
                    if let url = media.kind == .image ? media.url : media.posterUrl {
                        ProgressRemoteImage(url: url, alt: media.alt ?? L("Image"))
                    }
                    if media.kind == .video {
                        Label(L("Play video"), systemImage: "play.circle.fill")
                            .font(.title2).padding(8).background(.regularMaterial).allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("progress.media.\(media.id)")
            }
        }
    }
}

struct ProgressRemoteImage: View {
    let url: String
    let alt: String
    @StateObject private var loader: ProgressImageLoader
    @State private var attempt = 0

    init(url: String, alt: String) {
        self.url = url
        self.alt = alt
        _loader = StateObject(wrappedValue: ProgressImageLoader(url: url))
    }

    var body: some View {
        GeometryReader { geometry in
            if loader.imageURL == url, let image = loader.image {
                Image(nsImage: image).resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped().accessibilityLabel(alt)
                    .allowsHitTesting(false)
            } else {
                VStack {
                    if loader.failed {
                        Label(L("Image unavailable"), systemImage: "photo")
                        Button(L("Retry image")) {
                            attempt += 1
                        }
                    } else { ProgressView(L("Loading image…")) }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .task(id: "\(url):\(attempt)") { await loader.load(url) }
    }
}
