// Neutral image/video items and ordered full-screen presentation sessions.
// Exports MediaItem and MediaSession; URLs may reference remote resources or local files.
// Dependencies: Foundation; feature models convert into these items at their entry points.

import Foundation

struct MediaItem: Identifiable {
    enum Kind { case image, video }

    var id = UUID().uuidString
    let url: URL
    let kind: Kind
    /// A smaller display copy of an image, shown at once while `url` loads.
    var previewURL: URL? = nil
    var title: String? = nil
    var caption: String? = nil
    var aspectRatio: CGFloat? = nil
}

struct MediaSession: Identifiable {
    let id = UUID()
    let items: [MediaItem]
    let index: Int
}
