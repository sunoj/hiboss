// Decoded Box row thumbnails in an NSCache bounded by bitmap bytes; the disk cache covers misses.
// Exports BoxThumbnailMemory, which reports each evicted id so a visible row can reload it.
// Dependencies: UIKit on iOS and AppKit on macOS.

#if os(iOS)
import UIKit
#else
import AppKit
#endif

public final class BoxThumbnailMemory: NSObject, NSCacheDelegate, @unchecked Sendable {
    #if os(iOS)
    public typealias Image = UIImage
    public static let defaultCostLimit = 64 * 1024 * 1024
    #else
    public typealias Image = NSImage
    public static let defaultCostLimit = 96 * 1024 * 1024
    #endif

    /// Called with the item id of every evicted or removed image, on any thread.
    public var onEvict: (@Sendable (String) -> Void)?
    private let cache = NSCache<NSString, Entry>()

    private final class Entry {
        let id: String
        let image: Image
        init(id: String, image: Image) {
            self.id = id
            self.image = image
        }
    }

    #if os(macOS)
    public var costLimit: Int { cache.totalCostLimit }
    #endif

    public init(costLimit: Int = defaultCostLimit) {
        super.init()
        cache.totalCostLimit = costLimit
        cache.delegate = self
    }

    /// NSCache keeps its delegate unretained; detach it before the cache empties itself on dealloc.
    deinit { cache.delegate = nil }

    public subscript(id: String) -> Image? { cache.object(forKey: id as NSString)?.image }

    #if os(iOS)
    public func set(_ image: Image, for id: String) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(Entry(id: id, image: image), forKey: id as NSString, cost: Int(pixels) * 4)
    }
    #else
    public func set(_ image: Image, cost: Int, for id: String) {
        cache.setObject(Entry(id: id, image: image), forKey: id as NSString, cost: cost)
    }
    #endif

    public func remove(_ id: String) { cache.removeObject(forKey: id as NSString) }

    public func removeAll() { cache.removeAllObjects() }

    public func cache(_: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        if let entry = object as? Entry { onEvict?(entry.id) }
    }
}
