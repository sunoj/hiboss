// The single file an agent attaches with `hiboss send --file` or `--file-url`.
// Exports: MessageAttachment, built from `metadata.file_url` on a message.
// Dependencies: Foundation URL; only http(s) URLs become attachments.

import Foundation

public struct MessageAttachment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case image
        case file
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]

    public let url: URL
    public let kind: Kind

    /// Nil for anything other than an absolute http(s) URL with a host.
    public init?(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false
        else { return nil }
        self.url = url
        let ext = url.pathExtension.lowercased()
        kind = Self.imageExtensions.contains(ext) ? .image : .file
    }

    /// Last path component, or the host when the URL has no path.
    public var filename: String {
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? (url.host ?? url.absoluteString) : name
    }
}
