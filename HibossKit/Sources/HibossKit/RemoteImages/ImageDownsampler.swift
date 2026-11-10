// Decodes encoded image bytes with ImageIO, downsampled to a maximum pixel size.
// Exports DecodedImage and ImageDownsampler; never decodes the full-size bitmap first.
// Dependencies: Foundation, CoreGraphics and ImageIO.

import CoreGraphics
import Foundation
import ImageIO

public struct DecodedImage: @unchecked Sendable {
    public let cgImage: CGImage
    /// Pixel size of the encoded original, after its EXIF orientation.
    public let originalPixelSize: CGSize

    /// The image scale that keeps the original's point size: decoded pixels per original pixel.
    public var scale: CGFloat {
        guard originalPixelSize.width > 0 else { return 1 }
        return CGFloat(cgImage.width) / originalPixelSize.width
    }

    var cost: Int { cgImage.bytesPerRow * cgImage.height }
}

public enum ImageDownsampler {
    public enum Failure: Error { case undecodable }

    /// The longest side of the result is at most `maxPixelSize`; smaller images keep their size.
    public static func decode(_ data: Data, maxPixelSize: Int) throws -> DecodedImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else { throw Failure.undecodable }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw Failure.undecodable
        }
        return DecodedImage(cgImage: image, originalPixelSize: originalSize(source) ?? image.size)
    }

    private static func originalSize(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let rotated = (5...8).contains(orientation)
        return rotated ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}

private extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }
}
