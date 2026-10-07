// Shows bounded image/video thumbnails and the shared text before saving.
// Exports SharePreviewRow; semantic kind labels scale with Dynamic Type.
// Dependencies: SwiftUI, ImageIO, AVFoundation and ShareAttachment.

import AVFoundation
import ImageIO
import SwiftUI

struct SharePreviewRow: View {
    let item: ShareAttachment
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(alignment: .top) {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit()
                    .frame(width: 72, height: 72).accessibilityHidden(true)
            } else {
                Image(systemName: symbol).font(.title2).accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                kindLabel.font(.caption).foregroundStyle(.secondary)
                Text(verbatim: item.title).lineLimit(4).textSelection(.enabled)
            }
        }
        .task { await loadThumbnail() }
    }

    @ViewBuilder private var kindLabel: some View {
        switch item.kind {
        case .link: Text("Link")
        case .text: Text("Text")
        case .image: Text("Image")
        case .video: Text("Video")
        case .file: Text("File")
        }
    }

    private var symbol: String {
        switch item.kind {
        case .link: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "video"
        case .file: "doc"
        }
    }

    private func loadThumbnail() async {
        guard let url = item.media?.fileURL else { return }
        if item.kind == .image {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                  ] as CFDictionary) else { return }
            thumbnail = UIImage(cgImage: image)
        } else if item.kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 256, height: 256)
            if let result = try? await generator.image(at: .zero) {
                thumbnail = UIImage(cgImage: result.image)
            }
        }
    }
}
