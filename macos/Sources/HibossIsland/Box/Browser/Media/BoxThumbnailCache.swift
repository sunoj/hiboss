// Disk cache of Box thumbnails in the app's Caches folder, keyed by item id, with an LRU byte cap.
// Exports BoxThumbnailCache; reads refresh recency, stores evict the least recently used files.
// Dependencies: Foundation.

import Foundation

actor BoxThumbnailCache {
    static let standard = BoxThumbnailCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "HibossIsland", isDirectory: true)
            .appendingPathComponent("box-thumbnails", isDirectory: true),
        capacity: 100 * 1024 * 1024)

    private let directory: URL
    private let capacity: Int
    private let now: @Sendable () -> Date

    init(directory: URL, capacity: Int, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.capacity = capacity
        self.now = now
    }

    func data(for id: String) -> Data? {
        let url = file(id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
        return data
    }

    func store(_ data: Data, for id: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file(id), options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: file(id).path)
            evict()
        } catch { try? FileManager.default.removeItem(at: file(id)) }
    }

    func remove(_ id: String) { try? FileManager.default.removeItem(at: file(id)) }

    private func file(_ id: String) -> URL {
        let name = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return directory.appendingPathComponent(name + ".jpg")
    }

    private func evict() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (url: URL, date: Date, bytes: Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.date < $1.date }
        var total = entries.reduce(0) { $0 + $1.bytes }
        while total > capacity, !entries.isEmpty {
            let oldest = entries.removeFirst()
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.bytes
        }
    }
}
