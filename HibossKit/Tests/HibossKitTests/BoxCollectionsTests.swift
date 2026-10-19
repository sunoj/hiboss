// Covers Box collection models, likes, membership, and filtered requests.
// Dependencies: XCTest, Foundation URLProtocol, and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class BoxCollectionsTests: XCTestCase {
    private static let itemJSON = """
        {"id":"bx_1","boss_id":"b","boss_name":"Boss","kind":"text","text":"t",
         "tags":[],"source":"cli","has_media":false,"created_at":"created"}
        """
    private static let collectionJSON = """
        {"id":"bc_1","boss_id":"b","boss_name":"Boss","name":"Album","item_count":2,
         "cover_item_id":"bx_1","created_at":"created","updated_at":"updated"}
        """

    override func tearDown() {
        BoxCollectionsURLProtocol.handler = nil
        super.tearDown()
    }

    func testOldItemDefaultsAndNewItemRoundTrip() throws {
        let old = try JSONDecoder().decode(BoxItem.self, from: Data(Self.itemJSON.utf8))
        XCTAssertFalse(old.liked)
        XCTAssertNil(old.likedAt)
        XCTAssertEqual(old.collectionIDs, [])
        let newJSON = Self.itemJSON.dropLast()
            + #","liked":true,"liked_at":"liked","collection_ids":["bc_2","bc_1"]}"#
        let item = try JSONDecoder().decode(BoxItem.self, from: Data(newJSON.utf8))
        XCTAssertTrue(item.liked)
        XCTAssertEqual(item.likedAt, "liked")
        XCTAssertEqual(item.collectionIDs, ["bc_2", "bc_1"])
        XCTAssertEqual(
            try JSONDecoder().decode(BoxItem.self, from: JSONEncoder().encode(item)), item
        )
        let initialized = BoxItem(
            id: "bx_1", bossID: "b", bossName: "Boss", kind: .text, text: "t",
            source: .cli, createdAt: "created", liked: true, likedAt: "liked",
            collectionIDs: ["bc_2", "bc_1"]
        )
        XCTAssertEqual(initialized, item)
    }

    func testUnlikePayloadAndDefaultInitializer() throws {
        let json = String(Self.itemJSON.dropLast()) + #","liked":false,"liked_at":null,"collection_ids":[]}"#
        let item = try JSONDecoder().decode(BoxItem.self, from: Data(json.utf8))
        XCTAssertFalse(item.liked)
        XCTAssertNil(item.likedAt)
        XCTAssertEqual(item.collectionIDs, [])
        let initialized = BoxItem(id: "i", bossID: "b", bossName: "Boss", kind: .text, createdAt: "c")
        XCTAssertFalse(initialized.liked)
        XCTAssertNil(initialized.likedAt)
        XCTAssertEqual(initialized.collectionIDs, [])
    }

    func testCollectionDecodingInitializerAndRoundTrip() throws {
        let collection = try JSONDecoder().decode(BoxCollection.self, from: Data(Self.collectionJSON.utf8))
        let expected = BoxCollection(
            id: "bc_1", bossID: "b", bossName: "Boss", name: "Album", itemCount: 2,
            coverItemID: "bx_1", createdAt: "created", updatedAt: "updated"
        )
        XCTAssertEqual(collection, expected)
        XCTAssertEqual(
            try JSONDecoder().decode(BoxCollection.self, from: JSONEncoder().encode(expected)), expected
        )
        let noCover = Self.collectionJSON.replacingOccurrences(of: #""bx_1""#, with: "null")
        XCTAssertNil(try JSONDecoder().decode(BoxCollection.self, from: Data(noCover.utf8)).coverItemID)
    }

    func testListCollections() async throws {
        let api = try api(path: "/api/box/collections", method: "GET",
                          json: #"{"collections":["# + Self.collectionJSON + "]}")
        let collections = try await api.boxCollections()
        XCTAssertEqual(collections.first?.id, "bc_1")
        XCTAssertEqual(collections.count, 1)
    }

    func testCreateCollection() async throws {
        let api = try api(path: "/api/box/collections", method: "POST",
                          json: Self.collectionJSON, status: 201, name: "Album")
        let collection = try await api.createBoxCollection(name: "Album")
        XCTAssertEqual(collection.name, "Album")
    }

    func testRenameCollection() async throws {
        let api = try api(path: "/api/box/collections/bc_1", method: "PATCH",
                          json: Self.collectionJSON, name: "Album")
        let collection = try await api.renameBoxCollection(id: "bc_1", name: "Album")
        XCTAssertEqual(collection.id, "bc_1")
    }

    func testDeleteCollectionWithEmptyResponse() async throws {
        let api = try api(path: "/api/box/collections/bc_1", method: "DELETE", json: "", status: 204)
        try await api.deleteBoxCollection(id: "bc_1")
    }

    func testLikeAndUnlike() async throws {
        for liked in [true, false] {
            let json = String(Self.itemJSON.dropLast())
                + #","liked":\#(liked),"liked_at":null,"collection_ids":[]}"#
            let api = try api(path: "/api/box/items/bx_1/like",
                              method: liked ? "PUT" : "DELETE", json: json)
            let item = try await api.setBoxItem(id: "bx_1", liked: liked)
            XCTAssertEqual(item.liked, liked)
        }
    }

    func testAddAndRemoveMembership() async throws {
        for member in [true, false] {
            let ids = member ? #"["bc_1"]"# : "[]"
            let json = String(Self.itemJSON.dropLast()) + #","collection_ids":\#(ids)}"#
            let api = try api(path: "/api/box/collections/bc_1/items/bx_1",
                              method: member ? "PUT" : "DELETE", json: json)
            let item = try await api.setBoxItem(id: "bx_1", inCollection: "bc_1", member: member)
            XCTAssertEqual(item.collectionIDs, member ? ["bc_1"] : [])
        }
    }

    func testListSearchAndLatestQueriesCombineFilters() async throws {
        let filters = BoxFilters(
            kind: .text, since: "date", project: "p", boss: "b", liked: true, collection: "My Album & more"
        )
        for endpoint in ["", "/search", "/latest"] {
            var queries = [
                "kind": "text", "since": "date", "project": "p", "boss": "b",
                "liked": "1", "collection": "My Album & more"
            ]
            if endpoint != "/latest" {
                queries["limit"] = "7"
                queries["cursor"] = "cursor"
            }
            if endpoint == "/search" { queries["q"] = "words & more" }
            let json = endpoint == "/latest" ? Self.itemJSON : #"{"items":[],"next_cursor":null}"#
            let api = try api(path: "/api/box/items" + endpoint, method: "GET", json: json, queries: queries)
            switch endpoint {
            case "/search":
                _ = try await api.searchBoxItems(
                    query: "words & more", filters: filters, limit: 7, cursor: "cursor"
                )
            case "/latest":
                _ = try await api.latestBoxItem(filters: filters)
            default:
                _ = try await api.boxItems(filters: filters, limit: 7, cursor: "cursor")
            }
        }
    }

    func testDefaultFiltersOmitLikeAndCollection() async throws {
        let api = try api(path: "/api/box/items", method: "GET",
                          json: #"{"items":[],"next_cursor":null}"#, queries: ["limit": "20"])
        _ = try await api.boxItems()
    }

    func testCollectionMutationPropagatesConflict() async throws {
        let api = try api(path: "/api/box/collections", method: "POST",
                          json: "{}", status: 409, name: "Album")
        do {
            _ = try await api.createBoxCollection(name: "Album")
            XCTFail("Expected conflict")
        } catch HibossAPIError.requestFailed(let status, _) {
            XCTAssertEqual(status, 409)
        }
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? HibossAPIError.invalidResponse }
            if count == 0 { return data }
            data.append(buffer, count: count)
        }
    }

    private func api(
        path: String, method: String, json: String, status: Int = 200,
        name: String? = nil, queries: [String: String] = [:]
    ) throws -> HibossAPI {
        BoxCollectionsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, path)
            XCTAssertEqual(request.httpMethod, method)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let url = try XCTUnwrap(request.url)
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let actualQueries = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(actualQueries, queries)
            if let name {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let body = try Self.bodyData(from: request)
                XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: body), ["name": name])
            } else {
                XCTAssertNil(request.httpBody)
                XCTAssertNil(request.httpBodyStream)
            }
            let response = try XCTUnwrap(
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
            )
            return (response, Data(json.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BoxCollectionsURLProtocol.self]
        return HibossAPI(
            config: ConnectionConfig(
                serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "test-token"
            ),
            session: URLSession(configuration: config)
        )
    }
}

private final class BoxCollectionsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
