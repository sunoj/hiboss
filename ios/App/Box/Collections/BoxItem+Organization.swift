// Immutable Box item copies for optimistic likes and demo memberships.
// Preserves all content and provenance when organization metadata changes.
import HibossKit

extension BoxItem {
    func organized(liked: Bool? = nil, likedAt: String? = nil,
                   collectionIDs: [String]? = nil) -> BoxItem {
        BoxItem(id: id, bossID: bossID, bossName: bossName, kind: kind,
                text: text, url: url, note: note, project: project, tags: tags, source: source,
                hasMedia: hasMedia, mediaType: mediaType, mediaBytes: mediaBytes,
                width: width, height: height, durationMs: durationMs, createdAt: createdAt,
                addedBy: addedBy, liked: liked ?? self.liked,
                likedAt: liked == false ? nil : (likedAt ?? self.likedAt),
                collectionIDs: collectionIDs ?? self.collectionIDs, hasThumbnail: hasThumbnail)
    }
}
