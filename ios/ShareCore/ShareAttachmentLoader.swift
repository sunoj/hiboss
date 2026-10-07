// Copies host-provided attachments while their temporary URLs are valid.
// Exports ShareAttachmentLoader, bounded to the activation rule's four items.
// Dependencies: UIKit item providers, UTType and HibossKit upload models.

import HibossKit
import UIKit
import UniformTypeIdentifiers

@MainActor
enum ShareAttachmentLoader {
    static func load(_ providers: [NSItemProvider], directory: URL) async throws -> [ShareAttachment] {
        guard !providers.isEmpty else { throw ShareError.unsupported }
        guard providers.count <= SharePolicy.maximumAttachments else { throw ShareError.tooMany }
        var result: [ShareAttachment] = []
        for provider in providers {
            try Task.checkCancellation()
            guard let type = ShareAttachment.type(in: provider.registeredTypeIdentifiers) else {
                throw ShareError.unsupported
            }
            if type == .image || type == .movie {
                let file = try await copyFile(provider, type: type, directory: directory)
                let fileType = UTType(filenameExtension: file.pathExtension)
                let declaredType = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
                    .first { $0.conforms(to: type) && $0.preferredMIMEType != nil }
                let contentType = (fileType?.conforms(to: type) == true ? fileType : declaredType)?
                    .preferredMIMEType ?? (type == .image ? "image/jpeg" : "video/quicktime")
                result.append(ShareAttachment(kind: type == .image ? .image : .video,
                    title: provider.suggestedName ?? file.lastPathComponent, text: nil, url: nil,
                    media: BoxUpload.Media(fileURL: file, contentType: contentType)))
            } else {
                let value = try await loadText(provider, type: type)
                guard type != .url || ShareAttachment.text(value).kind == .link else {
                    throw ShareError.unsupported
                }
                result.append(ShareAttachment.text(value))
            }
        }
        try Task.checkCancellation()
        return result
    }

    private static func copyFile(
        _ provider: NSItemProvider, type: UTType, directory: URL
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? ShareError.preparation)
                    return
                }
                do {
                    let suffix = url.pathExtension.isEmpty
                        ? (type.preferredFilenameExtension ?? "") : url.pathExtension
                    let copy = directory.appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(suffix)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider, type: UTType) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let url = item as? URL { continuation.resume(returning: url.absoluteString) }
                else if let text = item as? String { continuation.resume(returning: text) }
                else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else { continuation.resume(throwing: error ?? ShareError.unsupported) }
            }
        }
    }
}
