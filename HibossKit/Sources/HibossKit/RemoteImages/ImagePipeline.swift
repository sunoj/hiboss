// Shared remote-image loader: decoded memory cache, persistent disk cache and one download per URL.
// Exports ImagePipeline; downloads outlive the view that asked, so a later request reuses them.
// Dependencies: Foundation, CryptoKit, ImageIO, BoxThumbnailCache, DecodedImageMemory, ImageDownsampler.

import CryptoKit
import Foundation
import ImageIO

public actor ImagePipeline {
    public static let shared = ImagePipeline(
        session: URLSession(configuration: ImagePipeline.sessionConfiguration),
        disk: BoxThumbnailCache(directory: ImagePipeline.cacheDirectory, capacity: 300 * 1024 * 1024))

    /// Responses are immutable; the disk cache replaces URLCache, whose entries cap at ~5% of its size.
    public static var sessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return config
    }

    private static var cacheDirectory: URL {
        var root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        #if os(macOS)
        root.appendPathComponent(Bundle.main.bundleIdentifier ?? "HibossIsland", isDirectory: true)
        #endif
        return root.appendingPathComponent("remote-images", isDirectory: true)
    }

    private let session: URLSession
    private let disk: BoxThumbnailCache?
    private nonisolated let memory: DecodedImageMemory
    private var downloads: [URL: Task<Data, Error>] = [:]

    public init(session: URLSession, disk: BoxThumbnailCache?,
                memoryCostLimit: Int = DecodedImageMemory.defaultCostLimit) {
        self.session = session
        self.disk = disk
        memory = DecodedImageMemory(costLimit: memoryCostLimit)
    }

    /// A decoded image already in memory, for a first frame without a loading state.
    public nonisolated func cachedImage(for url: URL, maxPixelSize: Int) -> DecodedImage? {
        memory[Self.memoryKey(url, maxPixelSize)]
    }

    /// `reload` starts a fresh download instead of joining one in flight; caches still answer first.
    public func image(for url: URL, maxPixelSize: Int, reload: Bool = false) async throws -> DecodedImage {
        let key = Self.memoryKey(url, maxPixelSize)
        if let hit = memory[key] { return hit }
        let data = try await data(for: url, reload: reload)
        let decoded = try await Task.detached(priority: .userInitiated) {
            try ImageDownsampler.decode(data, maxPixelSize: maxPixelSize)
        }.value
        memory.set(decoded, for: key)
        return decoded
    }

    private func data(for url: URL, reload: Bool) async throws -> Data {
        if !reload, let running = downloads[url] { return try await running.value }
        let task = Task.detached(priority: .userInitiated) { [session, disk] in
            try await Self.fetch(url, session: session, disk: disk)
        }
        downloads[url] = task
        defer { if downloads[url] == task { downloads[url] = nil } }
        return try await task.value
    }

    private static func fetch(_ url: URL, session: URLSession, disk: BoxThumbnailCache?) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let key = diskKey(url)
        if let cached = await disk?.data(for: key) { return cached }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              isImage(data) else { throw URLError(.badServerResponse) }
        if let disk { Task.detached(priority: .utility) { await disk.store(data, for: key) } }
        return data
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    private static func memoryKey(_ url: URL, _ maxPixelSize: Int) -> String {
        "\(maxPixelSize)|\(url.absoluteString)"
    }

    static func diskKey(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
