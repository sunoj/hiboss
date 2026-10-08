// Attachment identity, supported-type detection and upload size decisions.
// Exports ShareAttachment, SharePolicy and localized ShareError.
// Dependencies: Foundation, UniformTypeIdentifiers and HibossKit.

import Foundation
import HibossKit
import UniformTypeIdentifiers

struct ShareAttachment: Identifiable, Sendable {
    let id = UUID()
    let idempotencyKey = UUID().uuidString
    let kind: BoxItem.Kind
    let title: String
    let text: String?
    let url: String?
    let media: BoxUpload.Media?

    static func type(in identifiers: [String]) -> UTType? {
        for supported in [UTType.movie, .image, .fileURL, .url, .plainText] {
            if identifiers.contains(where: { UTType($0)?.conforms(to: supported) == true }) {
                return supported
            }
        }
        return identifiers.compactMap { UTType($0) }.first { $0.conforms(to: .item) }
    }

    static func text(_ value: String) -> ShareAttachment {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL {
            return ShareAttachment(kind: .file, title: url.lastPathComponent,
                text: url.lastPathComponent, url: nil, media: BoxUpload.Media(fileURL: url,
                    contentType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream"))
        }
        let isLink = URL(string: trimmed).map {
            ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host != nil
                && !trimmed.contains(where: { $0.isWhitespace })
        } ?? false
        return ShareAttachment(kind: isLink ? .link : .text, title: value,
            text: isLink ? nil : value, url: isLink ? trimmed : nil, media: nil)
    }
}

enum SharePolicy {
    static let maximumAttachments = 4
    static let imageBytes = 10 * 1024 * 1024
    static let videoBytes = 50 * 1024 * 1024
    static let fileBytes = 50 * 1024 * 1024
    static let textBytes = 16 * 1024

    enum Decision: Equatable { case upload, compress, refuse }

    static func decision(kind: BoxItem.Kind, bytes: Int, prepared: Bool = false) -> Decision {
        guard bytes > 0 else { return .refuse }
        switch kind {
        case .video: return prepared ? (bytes <= videoBytes ? .upload : .refuse) : .compress
        case .image: return bytes <= imageBytes ? .upload : (prepared ? .refuse : .compress)
        case .text: return bytes <= textBytes ? .upload : .refuse
        case .link: return bytes <= 8 * 1024 ? .upload : .refuse
        case .file: return bytes <= fileBytes ? .upload : .refuse
        }
    }
}

enum ShareError: Error, LocalizedError {
    case unsupported, tooMany, imageTooLarge, videoTooLarge, fileTooLarge, textTooLarge, preparation

    var errorDescription: String? {
        switch self {
        case .unsupported: String(localized: "Share a file, link, text, image, or video.")
        case .tooMany: String(localized: "Share up to 4 attachments at a time.")
        case .imageTooLarge: String(localized: "This image cannot fit within 10 MB. Choose a smaller image.")
        case .videoTooLarge:
            String(localized: "This video is still over 50 MB. Trim the clip and share it again.")
        case .fileTooLarge: String(localized: "Files must be 50 MB or smaller. Choose a smaller file.")
        case .textTooLarge: String(localized: "This text or note is too long. Keep it within 16 KB.")
        case .preparation: String(localized: "Could not prepare this attachment. Try sharing it again.")
        }
    }
}
