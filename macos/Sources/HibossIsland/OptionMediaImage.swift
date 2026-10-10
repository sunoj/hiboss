// Loads option attachment URLs on demand and decodes images away from the main actor.
// Exports: OptionMediaImage with bounded thumbnails and full-resolution viewing.
// Dependencies: SwiftUI, URLSession and ImageIO; uses the existing public attachment URLs.

import HibossKit
import ImageIO
import SwiftUI

struct OptionMediaImage: View {
    let url: String
    var maxPixelSize: Int? = nil
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if failed {
                if maxPixelSize == nil {
                    ContentUnavailableView(L("Image unavailable"), systemImage: "photo.badge.exclamationmark")
                } else {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2).foregroundStyle(.secondary)
                        .accessibilityLabel(L("Image unavailable"))
                }
            } else {
                ProgressView()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        guard let resource = URL(string: url) else {
            failed = true
            return
        }
        let size = maxPixelSize
        let worker = Task.detached(priority: .userInitiated) {
            try await Self.loadImage(from: resource, maxPixelSize: size)
        }
        do {
            let loaded = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            try Task.checkCancellation()
            image = loaded
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    nonisolated static func loadImage(from url: URL, maxPixelSize: Int? = nil) async throws -> CGImage {
        let (data, response) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw HibossAPIError.invalidResponse
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize ?? max(width, height),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
        try Task.checkCancellation()
        guard let decoded else { throw HibossAPIError.invalidResponse }
        return decoded
    }
}
