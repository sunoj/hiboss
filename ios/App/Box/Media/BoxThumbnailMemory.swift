// Decoded Box row thumbnails in an NSCache bounded by bitmap bytes; the disk cache covers misses.
// Exports BoxThumbnailMemory, which reports each evicted id so a visible row can reload it.
// Dependencies: UIKit.

import UIKit

final class BoxThumbnailMemory: NSObject, NSCacheDelegate, @unchecked Sendable {
    static let defaultCostLimit = 64 * 1024 * 1024

    /// Called with the item id of every evicted or removed image, on any thread.
    var onEvict: (@Sendable (String) -> Void)?
    private let cache = NSCache<NSString, Entry>()

    private final class Entry {
        let id: String
        let image: UIImage
        init(id: String, image: UIImage) {
            self.id = id
            self.image = image
        }
    }

    init(costLimit: Int = defaultCostLimit) {
        super.init()
        cache.totalCostLimit = costLimit
        cache.delegate = self
    }

    /// NSCache keeps its delegate unretained; detach it before the cache empties itself on dealloc.
    deinit { cache.delegate = nil }

    subscript(id: String) -> UIImage? { cache.object(forKey: id as NSString)?.image }

    func set(_ image: UIImage, for id: String) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(Entry(id: id, image: image), forKey: id as NSString, cost: Int(pixels) * 4)
    }

    func remove(_ id: String) { cache.removeObject(forKey: id as NSString) }

    func removeAll() { cache.removeAllObjects() }

    func cache(_: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        if let entry = object as? Entry { onEvict?(entry.id) }
    }
}
