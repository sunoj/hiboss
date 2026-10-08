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
            if type == .fileURL || type == .url || type == .plainText {
                let value = try await loadText(provider, type: type)
                if let source = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                   source.isFileURL {
                    let file = try copySource(source, type: .item,
                        suggestedName: provider.suggestedName, directory: directory)
                    result.append(try attachment(file.url, declaredType: file.type))
                } else {
                    guard type != .fileURL,
                          type != .url || ShareAttachment.text(value).kind == .link else {
                        throw ShareError.unsupported
                    }
                    result.append(ShareAttachment.text(value))
                }
            } else {
                let file = try await copyFile(provider, type: type, directory: directory)
                result.append(try attachment(file.url, declaredType: file.type))
            }
        }
        try Task.checkCancellation()
        return result
    }

    private static func copyFile(
        _ provider: NSItemProvider, type: UTType, directory: URL
    ) async throws -> (url: URL, type: UTType) {
        let suggestedName = provider.suggestedName
        let declaredType = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
            .first { $0.conforms(to: type) && $0.preferredMIMEType != nil } ?? type
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? ShareError.preparation)
                    return
                }
                do {
                    let copy = try copySource(url, type: declaredType,
                        suggestedName: suggestedName, directory: directory)
                    continuation.resume(returning: copy)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    nonisolated private static func copySource(
        _ source: URL, type: UTType, suggestedName: String?, directory: URL
    ) throws -> (url: URL, type: UTType) {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        guard values.isRegularFile == true else { throw ShareError.preparation }
        let sourceType = UTType(filenameExtension: source.pathExtension) ?? values.contentType
        let namedType = suggestedName.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) }
        let inferredType = sourceType?.preferredMIMEType != nil && sourceType != .data
            ? sourceType : (namedType ?? sourceType)
        let actualType = inferredType?.conforms(to: type) == true && inferredType?.preferredMIMEType != nil
            ? (inferredType ?? type) : type
        if !actualType.conforms(to: .image), !actualType.conforms(to: .movie),
           (values.fileSize ?? 0) > SharePolicy.fileBytes { throw ShareError.fileTooLarge }
        let suffix = source.pathExtension.isEmpty
            ? (actualType.preferredFilenameExtension ?? "") : source.pathExtension
        let originalName = (suggestedName?.isEmpty == false ? suggestedName : nil) ?? source.lastPathComponent
        var name = (originalName as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { throw ShareError.preparation }
        if (name as NSString).pathExtension.isEmpty, !suffix.isEmpty { name += ".\(suffix)" }
        let folder = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: copy)
        return (copy, actualType)
    }

    private static func attachment(_ file: URL, declaredType: UTType) throws -> ShareAttachment {
        let kind: BoxItem.Kind = declaredType.conforms(to: .image) ? .image
            : declaredType.conforms(to: .movie) ? .video : .file
        let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if kind == .file, SharePolicy.decision(kind: kind, bytes: bytes) == .refuse {
            throw bytes > SharePolicy.fileBytes ? ShareError.fileTooLarge : ShareError.preparation
        }
        let contentType = declaredType.preferredMIMEType
            ?? (kind == .image ? "image/jpeg"
                : kind == .video ? "video/quicktime" : "application/octet-stream")
        return ShareAttachment(kind: kind, title: file.lastPathComponent,
            text: kind == .file ? file.lastPathComponent : nil, url: nil,
            media: BoxUpload.Media(fileURL: file, contentType: contentType))
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
