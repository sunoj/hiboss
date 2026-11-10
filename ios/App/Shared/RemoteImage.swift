// Remote image presentation with stable geometry, delayed progress and explicit local retry.
// Exports RemoteImage for decision images, feed images, posters and full-screen viewers.
// Dependencies: SwiftUI, HibossKit ImagePipeline, PendingStateView, DemoDelay and Theme roles.

import HibossKit
import SwiftUI

struct RemoteImage<Content: View>: View {
    let url: URL?
    /// A smaller copy shown until `url` arrives, as in the full-screen viewer.
    var previewURL: URL? = nil
    var compact = false
    var retryIdentifier = "remote-image-retry"
    @ViewBuilder let content: (Image) -> Content
    @Environment(\.displayScale) private var displayScale
    @State private var attempt = 0
    @State private var pixels = 0
    @State private var loaded: (url: URL, image: Image)?
    @State private var preview: (url: URL, image: Image)?
    @State private var failed = false

    var body: some View {
        Group {
            if url == nil || missingLocalFile {
                unavailable
            } else if let image = shown {
                content(image)
            } else if failed {
                unavailable
            } else { waiting }
        }
        .onGeometryChange(for: Int.self) { proxy in
            RemoteImagePixels.bucket(for: proxy.size, scale: displayScale)
        } action: { bucket in
            if bucket > pixels { pixels = bucket }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(attempt)-\(pixels)") { await load() }
        .task(id: "\(previewURL?.absoluteString ?? "")-\(pixels)") { await loadPreview() }
    }

    /// The loaded image for this URL, a cached decode, or the preview while the original loads.
    private var shown: Image? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        if pixels > 0, !DemoDelay.isHeld("MEDIA"),
           let hit = ImagePipeline.shared.cachedImage(for: url, maxPixelSize: pixels) {
            return RemoteImagePixels.image(hit)
        }
        if let preview, preview.url == previewURL { return preview.image }
        return nil
    }

    private func load() async {
        guard let url, pixels > 0, !missingLocalFile else { return }
        failed = false
        do {
            try await DemoDelay.wait("MEDIA")
            let decoded = try await ImagePipeline.shared.image(
                for: url, maxPixelSize: pixels, reload: attempt > 0)
            guard !Task.isCancelled else { return }
            loaded = (url, RemoteImagePixels.image(decoded))
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func loadPreview() async {
        guard let previewURL, pixels > 0,
              let decoded = try? await ImagePipeline.shared.image(for: previewURL, maxPixelSize: pixels),
              !Task.isCancelled else { return }
        preview = (previewURL, RemoteImagePixels.image(decoded))
    }

    private var missingLocalFile: Bool {
        guard let url, url.isFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    private var waiting: some View {
        Group {
            if compact {
                CompactImageWait(onRetry: retry, retryIdentifier: retryIdentifier).id(attempt)
            } else {
                PendingStateView(title: String(localized: "Loading image…"), onRetry: { retry() })
                    .padding(16)
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 4) {
            if !compact {
                Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                    .font(.hbCallout).foregroundStyle(Theme.ink2)
            }
            Button(action: retry) {
                Label("Retry image", systemImage: "arrow.clockwise")
                    .font(.hbCaption).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(retryIdentifier)
            .accessibilityValue("Image unavailable")
        }
    }

    private func retry() {
        loaded = nil
        failed = false
        attempt += 1
    }
}

struct CompactImageWait: View {
    let onRetry: () -> Void
    var retryIdentifier = "remote-image-retry"
    @State private var slow = false

    var body: some View {
        Group {
            if slow {
                Button(action: onRetry) {
                    Label("Retry image", systemImage: "arrow.clockwise")
                        .font(.hbCaption).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(retryIdentifier)
                .accessibilityValue("Image is still loading")
            } else {
                DelayedProgressView().accessibilityLabel("Loading image…")
            }
        }
        .task {
            do { try await Task.sleep(for: .seconds(8)) }
            catch { return }
            slow = true
        }
    }
}
