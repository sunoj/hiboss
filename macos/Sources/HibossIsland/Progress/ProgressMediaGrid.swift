// Compact image grids and video posters that open the native large media viewer.
// Exports: ProgressMediaGrid and ProgressRemoteImage with explicit loading/retry states.
// Dependencies: SwiftUI, AppKit, URLSession and HibossKit public progress-media URLs.

import AppKit
import HibossKit
import SwiftUI

struct ProgressMediaGrid: View {
    let items: [ProgressMedia]
    let onOpen: (ProgressMedia) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
            count: items.count == 1 ? 1 : 2), spacing: 8) {
            ForEach(items) { media in
                ZStack {
                    Button { onOpen(media) } label: {
                        TodayStyle.ground.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(media.alt ?? (media.kind == .image ? L("Image") : L("Play video")))
                    .accessibilityHint(L("Open large viewer"))
                    if let url = media.kind == .image ? media.url : media.posterUrl {
                        ProgressRemoteImage(url: url, alt: media.alt ?? L("Image"), fills: true)
                    }
                    if media.kind == .video {
                        Label(L("Play video"), systemImage: "play.circle.fill")
                            .font(.title2).padding(8).background(.regularMaterial).allowsHitTesting(false)
                    }
                }
                .frame(height: items.count == 1 ? 200 : 160)
                .accessibilityIdentifier("progress.media.\(media.id)")
            }
        }
    }
}

struct ProgressRemoteImage: View {
    let url: String
    let alt: String
    var fills = false
    @State private var image: NSImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(nsImage: image).resizable()
                    .aspectRatio(contentMode: fills ? .fill : .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped().accessibilityLabel(alt)
                    .allowsHitTesting(false)
            } else {
                VStack {
                    if failed {
                        Label(L("Image unavailable"), systemImage: "photo")
                        Button(L("Retry image")) {
                            failed = false
                            attempt += 1
                        }
                    } else { ProgressView(L("Loading image…")) }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .task(id: attempt) { await load() }
    }

    private func load() async {
        guard let url = URL(string: url) else {
            failed = true
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let loaded = NSImage(data: data) else { throw HibossAPIError.invalidResponse }
            image = loaded
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
