// Metadata and media body for authenticated Box creation.
// Exports BoxUpload and BoxUploading for the native share workflow.
// Dependencies: Foundation and BoxItem.

import Foundation

public struct BoxUpload: Encodable, Sendable {
    public var text: String?
    public var url: String?
    public var note: String?
    public var project: String?
    public var source: BoxItem.Source
    public var media: Media?

    public struct Media: Sendable {
        public let fileURL: URL
        public let contentType: String

        public init(fileURL: URL, contentType: String) {
            self.fileURL = fileURL
            self.contentType = contentType
        }
    }

    enum CodingKeys: String, CodingKey { case text, url, note, project, source }

    public init(
        text: String? = nil, url: String? = nil, note: String? = nil,
        project: String? = nil, source: BoxItem.Source = .iosShare, media: Media? = nil
    ) {
        self.text = text
        self.url = url
        self.note = note
        self.project = project
        self.source = source
        self.media = media
    }
}

public protocol BoxUploading: Sendable {
    func createBoxItem(
        _ upload: BoxUpload, idempotencyKey: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BoxItem
}
