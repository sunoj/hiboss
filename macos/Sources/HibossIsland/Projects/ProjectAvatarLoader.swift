// Loads public avatar images in an isolated session with no boss credentials or cookies.
// Exports: ProjectAvatarLoader; nil image represents missing, loading, or failed avatars.
// Dependencies: AppKit image decoding and Foundation URLSession.

import AppKit
import Combine
import Foundation

@MainActor
final class ProjectAvatarLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.httpAdditionalHeaders = [:]
        return config
    }

    func load(_ url: URL?, session: URLSession? = nil) async {
        image = nil
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return }
        let client = session ?? URLSession(configuration: Self.configuration())
        defer { if session == nil { client.invalidateAndCancel() } }
        do {
            let (data, response) = try await client.data(for: URLRequest(url: url))
            guard !Task.isCancelled, let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return }
            image = NSImage(data: data)
        } catch {
            // Loading and failed requests keep the deterministic placeholder visible.
        }
    }
}
