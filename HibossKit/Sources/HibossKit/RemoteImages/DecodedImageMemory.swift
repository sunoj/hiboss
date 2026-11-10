// Decoded remote images in an NSCache bounded by bitmap bytes; the disk cache covers misses.
// Exports DecodedImageMemory, keyed by URL and requested pixel size.
// Dependencies: Foundation NSCache and DecodedImage.

import Foundation

public final class DecodedImageMemory: @unchecked Sendable {
    #if os(iOS)
    public static let defaultCostLimit = 96 * 1024 * 1024
    #else
    public static let defaultCostLimit = 128 * 1024 * 1024
    #endif

    private final class Entry {
        let image: DecodedImage
        init(_ image: DecodedImage) { self.image = image }
    }

    private let cache = NSCache<NSString, Entry>()

    public init(costLimit: Int) { cache.totalCostLimit = costLimit }

    subscript(key: String) -> DecodedImage? { cache.object(forKey: key as NSString)?.image }

    func set(_ image: DecodedImage, for key: String) {
        cache.setObject(Entry(image), forKey: key as NSString, cost: image.cost)
    }
}
