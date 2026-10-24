// Prepares media with medium-preset video export and bounded JPEG re-encoding.
// Exports ShareMediaPreparer; oversized output is refused before network upload, and image/video
// uploads get the shared 512 px JPEG thumbnail when one can be made.
// Dependencies: AVFoundation, ImageIO, UIKit and HibossKit.

@preconcurrency import AVFoundation
import HibossKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ShareMediaPreparer {
    static func prepare(_ media: BoxUpload.Media, kind: BoxItem.Kind) async throws -> BoxUpload.Media {
        let bytes = try FileManager.default.attributesOfItem(atPath: media.fileURL.path)[.size] as? Int ?? 0
        switch SharePolicy.decision(kind: kind, bytes: bytes) {
        case .upload: return media
        case .refuse:
            throw kind == .file && bytes > SharePolicy.fileBytes
                ? ShareError.fileTooLarge : ShareError.preparation
        case .compress:
            if kind == .video { return try await video(media.fileURL) }
            return try await Task.detached { try image(media.fileURL) }.value
        }
    }

    /// The `thumbnail` part for an image or video upload, written beside the prepared media.
    static func thumbnail(for media: BoxUpload.Media, kind: BoxItem.Kind) async -> BoxUpload.Media? {
        guard kind == .image || kind == .video,
              let data = await BoxThumbnailGenerator.thumbnail(for: media.fileURL, kind: kind) else { return nil }
        let output = media.fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + "-thumbnail.jpg")
        guard (try? data.write(to: output, options: [.atomic, .completeFileProtection])) != nil else { return nil }
        return BoxUpload.Media(fileURL: output, contentType: BoxThumbnailGenerator.contentType)
    }

    private static func image(_ url: URL) throws -> BoxUpload.Media {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ShareError.preparation }
        for dimension in [4096, 3072, 2048, 1024] {
            try Task.checkCancellation()
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else {
                throw ShareError.preparation
            }
            for quality in [0.85, 0.65, 0.45] {
                guard let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: quality) else {
                    throw ShareError.preparation
                }
                if SharePolicy.decision(kind: .image, bytes: data.count, prepared: true) == .upload {
                    let output = url.deletingLastPathComponent()
                        .appendingPathComponent(UUID().uuidString + ".jpg")
                    try data.write(to: output, options: [.atomic, .completeFileProtection])
                    return BoxUpload.Media(fileURL: output, contentType: "image/jpeg")
                }
            }
        }
        throw ShareError.imageTooLarge
    }

    private static func video(_ url: URL) async throws -> BoxUpload.Media {
        let output = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        try await ShareVideoExporter(source: url, output: output).run()
        let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard SharePolicy.decision(kind: .video, bytes: bytes, prepared: true) == .upload else {
            try? FileManager.default.removeItem(at: output)
            throw ShareError.videoTooLarge
        }
        return BoxUpload.Media(fileURL: output, contentType: "video/mp4")
    }
}
