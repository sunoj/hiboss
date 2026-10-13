// Shares bounded decoded progress images across rebuilt tiles and large viewers.
// Exports: ProgressImageLoader; initializes synchronously from successful URL cache entries.
// Dependencies: AppKit, Combine, URLSession and ProjectAvatarLoader's public-image configuration.

import AppKit
import Combine
import Foundation

@MainActor
final class ProgressImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var failed = false
    private(set) var imageURL: String

    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()

    init(url: String) {
        imageURL = url
        image = Self.images.object(forKey: url as NSString)
    }

    func load(_ address: String, session: URLSession? = nil) async {
        imageURL = address
        failed = false
        let key = address as NSString
        if let cached = Self.images.object(forKey: key) {
            image = cached
            return
        }
        image = nil
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else {
            failed = true
            return
        }
        let client = session ?? URLSession(configuration: ProjectAvatarLoader.configuration())
        defer { if session == nil { client.invalidateAndCancel() } }
        do {
            let (data, response) = try await client.data(from: url)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode), let decoded = NSImage(data: data)
            else { throw URLError(.cannotDecodeContentData) }
            let cost = decoded.representations.reduce(0) { total, rep in
                total + rep.pixelsWide * rep.pixelsHigh * 4
            }
            Self.images.setObject(decoded, forKey: key, cost: cost)
            image = decoded
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
