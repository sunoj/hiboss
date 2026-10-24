// Shared Box thumbnail generator: ImageIO downsample or video poster frame, encoded as JPEG.
// Exports BoxThumbnailGenerator; output keeps EXIF orientation, a 512 px longest side and 256 KiB,
// with any transparency composited onto white.
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
        let image = flattened(image)
        for quality in [0.7, 0.5] {
            guard let data = encode(image, quality: quality) else { return nil }
            if data.count <= limit { return data }
        }
        return nil
    }

    /// JPEG has no alpha channel, so translucent pixels are drawn over white first.
    static func flattened(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let rgb = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let space = rgb ?? CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
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
