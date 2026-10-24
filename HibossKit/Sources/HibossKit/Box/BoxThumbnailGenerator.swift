// Shared Box thumbnail generator: ImageIO downsample or video poster frame, encoded as JPEG.
// Exports BoxThumbnailGenerator; output keeps EXIF orientation, a 512 px longest side and 256 KiB.
// Dependencies: AVFoundation, ImageIO and UniformTypeIdentifiers.

@preconcurrency import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum BoxThumbnailGenerator {
    public static let maxPixelSize = 512
    public static let maxBytes = 256 * 1024
    public static let contentType = "image/jpeg"

    /// JPEG thumbnail for an image or video file, or nil when none fits the limits.
    public static func thumbnail(for url: URL, kind: BoxItem.Kind) async -> Data? {
        switch kind {
        case .image: downsample(url, maxPixelSize: maxPixelSize).flatMap { jpeg($0) }
        case .video: await poster(url).flatMap { jpeg($0) }
        default: nil
        }
    }

    /// Decodes at most `maxPixelSize` on the longest side, never the full-resolution bitmap.
    public static func downsample(_ url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func poster(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        return try? await generator.image(at: .zero).image
    }

    /// Quality 0.7, then once at 0.5; output still over `limit` is dropped.
    public static func jpeg(_ image: CGImage, limit: Int = maxBytes) -> Data? {
        for quality in [0.7, 0.5] {
            guard let data = encode(image, quality: quality) else { return nil }
            if data.count <= limit { return data }
        }
        return nil
    }

    static func encode(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
