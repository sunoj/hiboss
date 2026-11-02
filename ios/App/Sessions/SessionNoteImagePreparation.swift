// Bounded note image decoding and JPEG preparation for PhotosPicker data.
// Keeps animated GIF bytes and uses ImageIO downsampling for other formats.
import HibossKit
import ImageIO
import UIKit

struct SessionNoteImagePreparation {
    static func prepare(_ data: Data) throws -> SessionNoteUpload {
        let gif = data.starts(with: Data("GIF87a".utf8)) || data.starts(with: Data("GIF89a".utf8))
        let output: Data
        if gif { output = data }
        else {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048
                  ] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85)
            else { throw PreparationError.invalid }
            output = jpeg
        }
        guard output.count <= 10 * 1024 * 1024 else { throw PreparationError.tooLarge }
        return SessionNoteUpload(data: output, contentType: gif ? "image/gif" : "image/jpeg")
    }

    enum PreparationError: LocalizedError {
        case invalid, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalid: String(localized: "Unable to prepare image")
            case .tooLarge: String(localized: "Image exceeds 10 MB")
            }
        }
    }
}
