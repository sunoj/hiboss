// Classifies Island pasteboard representations and checks Box ingest limits before upload.
// Exports BoxDropInput, BoxDropPayload and localized BoxDropError.
// Dependencies: AppKit pasteboards, UniformTypeIdentifiers and HibossKit Box models.

import AppKit
import HibossKit
import UniformTypeIdentifiers

enum BoxDropError: Error, LocalizedError {
    case itemCount, unsupported, imageLimit, fileLimit, textLimit, noteLimit, unreadable

    var errorDescription: String? {
        switch self {
        case .itemCount: L("Drop up to 4 items at a time.")
        case .unsupported: L("Drop a file, image, text or web URL.")
        case .imageLimit: L("Images must be 10 MB or smaller. Nothing was uploaded.")
        case .fileLimit: L("Videos and files must be 50 MB or smaller. Nothing was uploaded.")
        case .textLimit: L("Text must be 16 KB or smaller. Nothing was uploaded.")
        case .noteLimit: L("The note must be 16 KB or smaller.")
        case .unreadable: L("This file is empty or cannot be read. Nothing was uploaded.")
        }
    }
}

enum BoxDropInput: Sendable {
    case file(URL)
    case image(Data, String)
    case text(String)

    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .init(UTType.jpeg.identifier), .tiff]
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .init(UTType.image.identifier)
    ] + imageTypes

    static func read(_ item: NSPasteboardItem) throws -> BoxDropInput {
        if let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL {
            return .file(url)
        }
        let types = imageTypes + item.types.filter { UTType($0.rawValue)?.conforms(to: .image) == true }
        for type in types {
            if let data = item.data(forType: type) {
                let mime = UTType(type.rawValue)?.preferredMIMEType ?? "image/tiff"
                return .image(data, mime)
            }
        }
        if let value = item.string(forType: .URL) {
            if let url = URL(string: value), url.isFileURL { return .file(url) }
            return .text(value)
        }
        if let value = item.string(forType: .string) { return .text(value) }
        throw BoxDropError.unsupported
    }
}

struct BoxDropPayload: Sendable {
    let kind: BoxItem.Kind
    let text: String?
    let url: String?
    struct Media: Sendable {
        let data: Data
        let mediaType: String
    }

    let upload: Media?
    let label: String

    static func validateSize(_ bytes: Int, kind: BoxItem.Kind) throws {
        let limit = kind == .image ? 10 * 1024 * 1024 : 50 * 1024 * 1024
        guard bytes <= limit else {
            throw kind == .image ? BoxDropError.imageLimit : BoxDropError.fileLimit
        }
        guard bytes > 0 else { throw BoxDropError.unreadable }
    }

    static func load(_ inputs: [BoxDropInput]) throws -> [BoxDropPayload] {
        guard (1...4).contains(inputs.count) else { throw BoxDropError.itemCount }
        return try inputs.map { input in
            switch input {
            case let .file(url): return try file(url)
            case let .image(data, mime):
                try validateSize(data.count, kind: .image)
                return BoxDropPayload(kind: .image, text: nil, url: nil,
                    upload: Media(data: data, mediaType: mime), label: L("Image"))
            case let .text(value): return try plainText(value)
            }
        }
    }

    private static func plainText(_ value: String) throws -> BoxDropPayload {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BoxDropError.unsupported }
        if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()),
           url.host != nil {
            guard trimmed.utf8.count <= 8 * 1024 else { throw BoxDropError.unsupported }
            return BoxDropPayload(kind: .link, text: nil, url: trimmed, upload: nil, label: trimmed)
        }
        guard value.utf8.count <= 16 * 1024 else { throw BoxDropError.textLimit }
        return BoxDropPayload(kind: .text, text: value, url: nil, upload: nil, label: value)
    }

    private static func file(_ url: URL) throws -> BoxDropPayload {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true, let bytes = values.fileSize else { throw BoxDropError.unreadable }
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
        let kind: BoxItem.Kind = type?.conforms(to: .image) == true ? .image
            : type?.conforms(to: .movie) == true ? .video : .file
        try validateSize(bytes, kind: kind)
        let data = try Data(contentsOf: url)
        try validateSize(data.count, kind: kind)
        return BoxDropPayload(kind: kind, text: nil, url: nil,
            upload: Media(data: data, mediaType: type?.preferredMIMEType ?? "application/octet-stream"),
            label: url.lastPathComponent)
    }
}
