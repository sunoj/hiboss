// Resolves public Markdown attachments and reads bounded UTF-8 documents on demand.
// Exports: MarkdownAttachmentInfo and MarkdownAttachmentDocument.
// Dependencies: Foundation URLSession; response filenames identify extensionless uploads.

import Foundation

public struct MarkdownAttachmentInfo: Equatable, Sendable {
    public let filename: String
    public let isMarkdown: Bool

    public init(url: URL, response: URLResponse? = nil) {
        filename = response?.suggestedFilename ?? url.lastPathComponent
        let suffix = (filename as NSString).pathExtension.lowercased()
        let mime = response?.mimeType?.lowercased()
        isMarkdown = ["md", "markdown"].contains(suffix)
            || ["text/markdown", "text/x-markdown"].contains(mime ?? "")
    }
}

public enum MarkdownAttachmentDocument {
    public static let maximumBytes = 2 * 1024 * 1024

    public static func inspect(_ url: URL, session: URLSession = .shared) async throws
        -> MarkdownAttachmentInfo {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        let (_, response) = try await session.data(for: request)
        try validate(response)
        return MarkdownAttachmentInfo(url: url, response: response)
    }

    public static func read(_ url: URL, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (stream, response) = try await session.bytes(for: request)
        try validate(response)
        guard response.expectedContentLength <= maximumBytes else { throw DocumentError.tooLarge }
        var data = Data()
        for try await byte in stream {
            guard data.count < maximumBytes else { throw DocumentError.tooLarge }
            data.append(byte)
        }
        guard let source = String(data: data, encoding: .utf8) else { throw DocumentError.invalidText }
        return source.hasPrefix("\u{feff}") ? String(source.dropFirst()) : source
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DocumentError.unavailable
        }
    }

    public enum DocumentError: LocalizedError {
        case unavailable, tooLarge, invalidText

        public var errorDescription: String? {
            switch self {
            case .unavailable: kitL("The document could not be loaded.")
            case .tooLarge:
                kitL("This document is too large to preview. Open the original file instead.")
            case .invalidText:
                kitL("This file is not a UTF-8 Markdown document.")
            }
        }
    }
}
