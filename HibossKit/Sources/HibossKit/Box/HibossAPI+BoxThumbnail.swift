// Authenticated Box thumbnail download and replacement endpoints.
// Exports HibossAPI BoxThumbnailServing conformance; 404/405 mean the server lacks the item or route.
// Dependencies: Foundation URLSession and the existing boss request helpers.

import Foundation

extension HibossAPI: BoxThumbnailServing {
    public func boxThumbnailURL(id: String) -> URL {
        config.serverURL.appendingPathComponent("api/box/items")
            .appendingPathComponent(id).appendingPathComponent("thumbnail")
    }

    public func downloadBoxThumbnail(id: String) async throws -> Data {
        var request = authorizedRequest(url: boxThumbnailURL(id: id), method: "GET")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data = try await validatedData(for: request)
        return data
    }

    public func uploadBoxThumbnail(
        id: String, data: Data, contentType: String = BoxThumbnailGenerator.contentType
    ) async throws -> BoxItem {
        var request = authorizedRequest(url: boxThumbnailURL(id: id), method: "PUT")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await session.upload(for: request, from: data)
        try await validate(response)
        return try decoder.decode(BoxItem.self, from: body)
    }
}
