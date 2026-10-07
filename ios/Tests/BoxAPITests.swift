// Exercises every Box HTTP operation through URLSession and the production API client.
// Exports BoxAPITests; verifies boss auth, query encoding, mutations and private downloads.
// Dependencies: XCTest, Foundation, HibossKit and BoxModelTests' server-shaped fixture.

import HibossKit
import XCTest

final class BoxAPITests: XCTestCase {
    private func api(_ scenario: String = "success") throws -> HibossAPI {
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [BoxURLProtocol.self]
        return HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://box.example/\(scenario)")), bossToken: "test-token"
        ), session: URLSession(configuration: session))
    }

    func testListAndSearchSendEveryFilterAndOpaqueCursorUnchanged() async throws {
        let api = try api()
        let filters = BoxFilters(kind: .image, since: "1h", project: "project & layout", boss: "Box Owner")
        let page = try await api.boxItems(filters: filters, limit: 7, cursor: "opaque_server-cursor")
        XCTAssertEqual(page.items.first?.bossName, "Owner")
        XCTAssertEqual(page.nextCursor, "opaque_server-cursor")
        let search = try await api.searchBoxItems(
            query: "layout & 参考", filters: filters, limit: 7, cursor: page.nextCursor)
        XCTAssertEqual(search, page)
    }

    func testLatestShowAndPatchDecodeDirectItems() async throws {
        let api = try api()
        let latest = try await api.latestBoxItem(filters: BoxFilters(kind: .image))
        let shown = try await api.boxItem(id: latest.id)
        XCTAssertEqual(latest, shown)
        let patched = try await api.patchBoxItem(id: shown.id, patch: BoxPatch(
            note: .value(nil), project: .value("new"), tags: ["reference"]))
        XCTAssertEqual(patched.id, shown.id)
    }

    func testPrivateMediaRequestAndDownloadUseBossAuthorization() async throws {
        let api = try api()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let request = api.boxMediaRequest(id: "bx_reference")
        XCTAssertEqual(request.url, api.boxMediaURL(id: "bx_reference"))
        XCTAssertEqual(request.url?.path, "/success/api/box/items/bx_reference/media")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(request.url?.query)
        try await api.downloadBoxMedia(id: "bx_reference", to: url)
        XCTAssertEqual(try Data(contentsOf: url), Data("private bytes".utf8))
    }

    func testSoftDeleteAndPurgeUseTheCorrectQueryAndAccept204() async throws {
        let api = try api()
        try await api.deleteBoxItem(id: "bx_reference")
        try await api.deleteBoxItem(id: "bx_reference", purge: true)
    }

    func testFailedMediaDoesNotWriteServerErrorBytesAndLatest404Throws() async throws {
        let api = try api("missing")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try await api.downloadBoxMedia(id: "bx_reference", to: url)
            XCTFail("Unauthorized bytes must not be saved")
        } catch let error as HibossAPIError {
            guard case .requestFailed(status: 404, _) = error else { return XCTFail("Unexpected error") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        do {
            _ = try await api.latestBoxItem()
            XCTFail("An empty latest result must report 404")
        } catch let error as HibossAPIError {
            guard case .requestFailed(status: 404, _) = error else { return XCTFail("Unexpected error") }
        }
    }
}

private final class BoxURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return XCTFail("Missing request URL") }
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertTrue(url.path.contains("/api/box/items"))
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        let body: String
        let status: Int
        if url.path.hasPrefix("/missing") {
            status = 404
            body = "not found"
        } else if request.httpMethod == "DELETE" {
            XCTAssertEqual(url.lastPathComponent, "bx_reference")
            XCTAssertTrue(query.isEmpty || query == ["purge": "1"])
            status = 204
            body = ""
        } else {
            status = 200
            body = responseBody(url: url, query: query)
        }
        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil
        ) else {
            return XCTFail("Invalid response URL")
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func responseBody(url: URL, query: [String: String]) -> String {
        if url.lastPathComponent == "media" { return "private bytes" }
        if request.httpMethod == "PATCH" {
            let json = try? JSONSerialization.jsonObject(with: requestBody()) as? [String: Any]
            XCTAssertTrue(json?["note"] is NSNull)
            XCTAssertEqual(json?["project"] as? String, "new")
            XCTAssertEqual(json?["tags"] as? [String], ["reference"])
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        } else if url.lastPathComponent == "latest" {
            XCTAssertEqual(query, ["kind": "image"])
        } else if url.lastPathComponent == "items" || url.lastPathComponent == "search" {
            XCTAssertEqual(query["kind"], "image")
            XCTAssertEqual(query["since"], "1h")
            XCTAssertEqual(query["project"], "project & layout")
            XCTAssertEqual(query["boss"], "Box Owner")
            XCTAssertEqual(query["limit"], "7")
            XCTAssertEqual(query["cursor"], "opaque_server-cursor")
            if url.lastPathComponent == "search" { XCTAssertEqual(query["q"], "layout & 参考") }
            return "{\"items\":[\(BoxModelTests.itemJSON)],\"next_cursor\":\"opaque_server-cursor\"}"
        }
        return BoxModelTests.itemJSON
    }

    private func requestBody() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }

    override func stopLoading() {}
}
