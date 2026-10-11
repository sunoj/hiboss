// Identifies image/video files at attachment and Box opening boundaries.
// Exports MediaFileKind; document files continue to use their native document destinations.
// Dependencies: Foundation and MediaItem.

import Foundation

enum MediaFileKind {
    static func kind(filename: String, contentType: String? = nil) -> MediaItem.Kind? {
        if contentType?.hasPrefix("image/") == true { return .image }
        if contentType?.hasPrefix("video/") == true { return .video }
        let suffix = (filename as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"].contains(suffix) {
            return .image
        }
        if ["mp4", "mov", "m4v", "webm"].contains(suffix) { return .video }
        return nil
    }
}
