// Creates Box items with JSON metadata or a single multipart media attachment.
// Exports BoxCreate, BoxUpload and HibossAPI.createBoxItem using existing boss authentication.
// Dependencies: Foundation, BoxItem and HibossAPI request helpers.

import Foundation

public struct BoxCreate: Encodable, Sendable {
    public let text: String?
    public let url: String?
    public let note: String?
    public let source: BoxItem.Source

    public init(text: String? = nil, url: String? = nil, note: String? = nil, source: BoxItem.Source) {
        self.text = text
        self.url = url
        self.note = note
        self.source = source
    }
}

public struct BoxUpload: Sendable {
    public let data: Data
    public let mediaType: String

    public init(data: Data, mediaType: String) {
        self.data = data
        self.mediaType = mediaType
    }
}

extension HibossAPI {
    public func createBoxItem(
        _ item: BoxCreate, upload: BoxUpload? = nil, idempotencyKey: String
    ) async throws -> BoxItem {
        var request = authorizedRequest(
            url: config.serverURL.appendingPathComponent("api/box/items"), method: "POST"
        )
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        let metadata = try JSONEncoder().encode(item)
        if let upload {
            let boundary = "HiBoss-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = multipart(metadata: metadata, upload: upload, boundary: boundary)
        } else {
            request.httpBody = metadata
        }
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(BoxItem.self, from: data)
    }

    private func multipart(metadata: Data, upload: BoxUpload, boundary: String) -> Data {
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"meta\"\r\n\r\n".utf8)
        body.append(metadata)
        body.append(Data(("\r\n--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"attachment\"\r\n"
            + "Content-Type: \(upload.mediaType)\r\n\r\n").utf8))
        body.append(upload.data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
