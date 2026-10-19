// Authenticated Box collection management, membership, and like endpoints.
// Exports HibossAPI methods returning collection metadata or updated items.
// Dependencies: Box models and shared credential/request helpers.

import Foundation

extension HibossAPI {
    private var boxCollectionsURL: URL {
        config.serverURL.appendingPathComponent("api/box/collections")
    }

    public func boxCollections() async throws -> [BoxCollection] {
        struct Response: Decodable { let collections: [BoxCollection] }
        return try await decode(Response.self, from: boxCollectionsURL, context: "Box collections")
            .collections
    }

    public func createBoxCollection(name: String) async throws -> BoxCollection {
        try await writeBoxCollection(url: boxCollectionsURL, method: "POST", name: name)
    }

    public func renameBoxCollection(id: String, name: String) async throws -> BoxCollection {
        try await writeBoxCollection(
            url: boxCollectionsURL.appendingPathComponent(id), method: "PATCH", name: name
        )
    }

    public func deleteBoxCollection(id: String) async throws {
        try await send("DELETE", url: boxCollectionsURL.appendingPathComponent(id))
    }

    public func setBoxItem(id: String, liked: Bool) async throws -> BoxItem {
        let url = config.serverURL.appendingPathComponent("api/box/items")
            .appendingPathComponent(id).appendingPathComponent("like")
        return try await decode(
            BoxItem.self, from: url, method: liked ? "PUT" : "DELETE", context: "Box like"
        )
    }

    public func setBoxItem(id: String, inCollection: String, member: Bool) async throws -> BoxItem {
        let url = boxCollectionsURL.appendingPathComponent(inCollection)
            .appendingPathComponent("items").appendingPathComponent(id)
        return try await decode(
            BoxItem.self, from: url, method: member ? "PUT" : "DELETE", context: "Box membership"
        )
    }

    private func writeBoxCollection(url: URL, method: String, name: String) async throws -> BoxCollection {
        struct Payload: Encodable { let name: String }
        var request = authorizedRequest(url: url, method: method)
        request.httpBody = try JSONEncoder().encode(Payload(name: name))
        let (data, response) = try await session.data(for: request)
        try await validate(response)
        return try decoder.decode(BoxCollection.self, from: data)
    }
}
