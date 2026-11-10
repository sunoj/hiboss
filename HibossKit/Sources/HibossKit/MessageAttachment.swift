// The single file an agent attaches with `hiboss send --file` or `--file-url`.
// Exports: MessageAttachment, built from `metadata.file_url` and its optional `file_thumbnail_url`.
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
    /// A small display copy of an image attachment; nil when absent or not a valid http(s) URL.
    public let thumbnailURL: URL?

    /// The URL a card or feed shows: the display copy when present, otherwise the original.
    public var displayURL: URL { thumbnailURL ?? url }

    /// Nil for anything other than an absolute http(s) URL with a host.
    public init?(urlString: String, thumbnailURLString: String? = nil) {
        guard let url = Self.webURL(urlString) else { return nil }
        self.url = url
        let ext = url.pathExtension.lowercased()
        kind = Self.imageExtensions.contains(ext) ? .image : .file
        thumbnailURL = kind == .image ? thumbnailURLString.flatMap(Self.webURL) : nil
    }

    /// An absolute http(s) URL with a host, or nil.
    public static func webURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// Last path component, or the host when the URL has no path.
    public var filename: String {
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? (url.host ?? url.absoluteString) : name
    }
}
