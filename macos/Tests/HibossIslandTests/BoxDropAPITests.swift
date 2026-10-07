// Verifies JSON and multipart drop requests through the production Box client.
// Exports BoxDropAPITests and an isolated URLProtocol transport with synthetic credentials.
// Dependencies: XCTest, Foundation and HibossKit create operations.

import Foundation
import HibossKit
import os
import XCTest
@testable import HibossIsland

@MainActor
final class BoxDropAPITests: XCTestCase {
    func testJSONDropPostsSourceNoteAndIdempotencyHeader() async throws {
        let api = try client()
        let item = try await api.createBoxItem(
            BoxCreate(text: "Reference text", note: "Use this", source: .macDrop), idempotencyKey: "json-key"
        )
        XCTAssertEqual(item.id, "bx_test")
        XCTAssertEqual(item.source, .macDrop)
    }

    func testMultipartDropPostsOneFileWithMetadata() async throws {
        let api = try client()
        let item = try await api.createBoxItem(
            BoxCreate(note: "Use this", source: .macDrop),
            upload: BoxUpload(data: Data("image bytes".utf8), mediaType: "image/png"),
            idempotencyKey: "media-key"
        )
        XCTAssertEqual(item.kind, .image)
    }

    func testWebURLDropPostsURLInsteadOfText() async throws {
        let item = try await client().createBoxItem(
            BoxCreate(url: "https://example.com/reference", note: "Use this", source: .macDrop),
            idempotencyKey: "link-key"
        )
        XCTAssertEqual(item.kind, .link)
    }

    func testHTTPFailureKeepsDraftAndRepeatsSameRequestOnRetry() async throws {
        let api = try client(host: "retry.box-test.invalid")
        var attempts = 0
        let store = BoxDropStore { item, upload, key in
            attempts += 1
            _ = try await api.createBoxItem(item, upload: upload, idempotencyKey: key)
        }
        await store.prepare([.text("Reference text")])
        store.note = "Use this"
        let key = try XCTUnwrap(store.keys.first)
        await store.save()
        XCTAssertEqual(store.phase, .failed)
        XCTAssertEqual(store.note, "Use this")
        await store.save()
        XCTAssertEqual(store.phase, .saved)
        XCTAssertEqual(store.keys, [key])
        XCTAssertEqual(attempts, 2)
    }

    private func client(host: String = "box-test.invalid") throws -> HibossAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DropURLProtocol.self]
        return HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://\(host)")), bossToken: "synthetic-box-token"
        ), session: URLSession(configuration: config))
    }
}

private final class DropURLProtocol: URLProtocol, @unchecked Sendable {
    private static let attempts = OSAllocatedUnfairLock(initialState: [String: Int]())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/api/box/items")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-box-token")
            let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
            let attempt = Self.attempts.withLock { counts in
                counts[key, default: 0] += 1
                return counts[key, default: 0]
            }
            let isMedia = request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/") == true
            let bytes = body()
            if isMedia {
                try checkMultipart(bytes)
            } else {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let metadata = try JSONSerialization.jsonObject(with: bytes) as? [String: String]
                let content = key == "link-key" ? ["url": "https://example.com/reference"]
                    : ["text": "Reference text"]
                XCTAssertEqual(metadata, content.merging(["source": "mac-drop", "note": "Use this"]) { $1 })
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: url.host == "retry.box-test.invalid" && attempt == 1 ? 503 : 200,
                httpVersion: nil, headerFields: nil
            ))
            let item = BoxItem(id: "bx_test", bossID: "boss", bossName: "Test Boss",
                kind: isMedia ? .image : key == "link-key" ? .link : .text,
                source: .macDrop, createdAt: "2026-10-08T00:00:00Z")
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONEncoder().encode(item))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func checkMultipart(_ bytes: Data) throws {
        let body = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let type = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try XCTUnwrap(type.components(separatedBy: "boundary=").last)
        XCTAssertTrue(body.hasPrefix("--\(boundary)\r\n"))
        XCTAssertTrue(body.hasSuffix("\r\n--\(boundary)--\r\n"))
        XCTAssertTrue(body.contains("name=\"meta\""))
        XCTAssertEqual(body.components(separatedBy: "name=\"file\"").count - 1, 1)
        XCTAssertTrue(body.contains("Content-Type: image/png\r\n\r\nimage bytes"))
        let metadata = try XCTUnwrap(body.components(separatedBy: "\r\n\r\n").dropFirst().first)
            .components(separatedBy: "\r\n--")[0]
        let json = try JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: String]
        XCTAssertEqual(json, ["source": "mac-drop", "note": "Use this"])
    }

    private func body() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }

    override func stopLoading() {}
}
