// Caches rasterized project avatars for native progress-menu items.
// Exports: ProjectAvatarRendererCache.
// Dependencies: AppKit, SwiftUI, HibossKit and ProjectAvatarContent.

import AppKit
import Combine
import HibossKit
import SwiftUI

@MainActor
final class ProjectAvatarRendererCache: ObservableObject {
    /// Bounded: NSCache evicts under memory pressure and beyond `countLimit`.
    private let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    private static func key(_ project: ProjectIdentity, _ source: NSImage?, _ appearance: String,
                            _ scale: CGFloat) -> NSString {
        let sourceID = source.map { String(describing: ObjectIdentifier($0)) } ?? "-"
        let parts = [project.id, project.slug, project.displayName,
                     project.avatarURL?.absoluteString ?? "-", appearance, "\(scale)", sourceID]
        return parts.joined(separator: "\u{1F}") as NSString
    }

    func image(for project: ProjectIdentity, source: NSImage?, appearance: String,
               scale: CGFloat) -> NSImage? {
        let key = Self.key(project, source, appearance, scale)
        if let image = images.object(forKey: key) { return image }
        let renderer = ImageRenderer(content: ProjectAvatarContent(
            placeholder: project.placeholder, image: source, size: 16))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}
