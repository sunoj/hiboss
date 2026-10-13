// Caches decoded public avatars and loads misses without boss credentials or cookies.
// Exports: ProjectAvatarLoader; nil image represents missing, loading, or failed avatars.
// Dependencies: AppKit image decoding and Foundation URLSession.

import AppKit
import Combine
import Foundation

@MainActor
final class ProjectAvatarLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    init(url: URL? = nil) {
        image = Self.validatedURL(url).flatMap {
            Self.images.object(forKey: $0.absoluteString as NSString)
        }
    }

    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpAdditionalHeaders = [:]
        return config
    }

    func load(_ url: URL?, session: URLSession? = nil) async {
        guard let url = Self.validatedURL(url) else {
            image = nil
            return
        }
        let key = url.absoluteString as NSString
        if let cached = Self.images.object(forKey: key) {
            image = cached
            return
        }
        image = nil
        let client = session ?? URLSession(configuration: Self.configuration())
        defer { if session == nil { client.invalidateAndCancel() } }
        do {
            let (data, response) = try await client.data(for: URLRequest(url: url))
            guard !Task.isCancelled, let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode), let decoded = NSImage(data: data)
            else { return }
            Self.images.setObject(decoded, forKey: key)
            image = decoded
        } catch {
            // Loading and failed requests keep the deterministic placeholder visible.
        }
    }

    private static func validatedURL(_ url: URL?) -> URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
