// Authenticated Box list, search, item, media and mutation endpoints.
// Exports HibossAPI BoxServing conformance and metadata editing methods.
// Dependencies: Box models and the existing boss credential/request helpers.

import Foundation

extension HibossAPI: BoxServing {
    private var boxURL: URL {
        config.serverURL.appendingPathComponent("api/box/items")
    }

    public func boxItems(
        filters: BoxFilters = BoxFilters(), limit: Int = 20, cursor: String? = nil
    ) async throws -> BoxPage {
        try await decode(BoxPage.self, from: boxURL.appending(
            queryItems: boxQuery(filters, limit: limit, cursor: cursor)
        ), context: "Box items")
    }

    public func latestBoxItem(filters: BoxFilters = BoxFilters()) async throws -> BoxItem {
        try await decode(BoxItem.self, from: boxURL.appendingPathComponent("latest")
            .appending(queryItems: filters.queryItems), context: "latest Box item")
    }

    public func searchBoxItems(
        query: String, filters: BoxFilters = BoxFilters(), limit: Int = 20, cursor: String? = nil
    ) async throws -> BoxPage {
        try await decode(BoxPage.self, from: boxURL.appendingPathComponent("search").appending(
            queryItems: [URLQueryItem(name: "q", value: query)]
                + boxQuery(filters, limit: limit, cursor: cursor)
        ), context: "Box search")
    }

    public func boxItem(id: String) async throws -> BoxItem {
        try await decode(BoxItem.self, from: boxURL.appendingPathComponent(id), context: "Box item")
    }

    public func boxMediaURL(id: String) -> URL {
        boxURL.appendingPathComponent(id).appendingPathComponent("media")
    }

    public func boxMediaRequest(id: String) -> URLRequest {
        var request = authorizedRequest(url: boxMediaURL(id: id), method: "GET")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public func downloadBoxMedia(id: String, to destination: URL) async throws {
        let (data, response) = try await session.data(for: boxMediaRequest(id: id))
        try validate(response)
        try Task.checkCancellation()
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
    }

    public func patchBoxItem(id: String, patch: BoxPatch) async throws -> BoxItem {
        var request = authorizedRequest(url: boxURL.appendingPathComponent(id), method: "PATCH")
        request.httpBody = try JSONEncoder().encode(patch)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try decoder.decode(BoxItem.self, from: data)
    }

    public func deleteBoxItem(id: String, purge: Bool = false) async throws {
        let url = boxURL.appendingPathComponent(id)
        try await send("DELETE", url: purge ? url.appending(queryItems: [
            URLQueryItem(name: "purge", value: "1")
        ]) : url)
    }

    private func boxQuery(_ filters: BoxFilters, limit: Int, cursor: String?) -> [URLQueryItem] {
        var items = filters.queryItems + [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        return items
    }
}
