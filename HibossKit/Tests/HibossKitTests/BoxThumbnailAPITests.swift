// Covers Box thumbnail decoding defaults and the thumbnail download, PUT and multipart requests.
// Dependencies: XCTest, Foundation URLProtocol, and HibossKit.

import Foundation
import XCTest
@testable import HibossKit

final class BoxThumbnailAPITests: XCTestCase {
    private static let itemJSON = """
        {"id":"bx_1","boss_id":"b","boss_name":"Boss","kind":"image","tags":[],"source":"cli",
         "has_media":true,"media_type":"image/jpeg","created_at":"created"}
        """
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])

    override func tearDown() {
        BoxThumbnailURLProtocol.handler = nil
        super.tearDown()
    }

    func testHasThumbnailDefaultsToFalseOnOlderServersAndRoundTrips() throws {
        let old = try JSONDecoder().decode(BoxItem.self, from: Data(Self.itemJSON.utf8))
        XCTAssertFalse(old.hasThumbnail)
        let item = try JSONDecoder().decode(BoxItem.self, from: Self.json(hasThumbnail: true))
        XCTAssertTrue(item.hasThumbnail)
        XCTAssertEqual(try JSONDecoder().decode(BoxItem.self, from: JSONEncoder().encode(item)), item)
        XCTAssertFalse(BoxItem(id: "i", bossID: "b", bossName: "B", kind: .image, createdAt: "c").hasThumbnail)
    }

    func testDownloadThumbnailUsesAuthorizedGET() async throws {
        let data = try await api { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/box/items/bx_1/thumbnail")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (200, self.jpeg)
        }.downloadBoxThumbnail(id: "bx_1")
        XCTAssertEqual(data, jpeg)
    }

    func testMissingThumbnailThrows404() async throws {
        do {
            _ = try await api { _ in (404, Data()) }.downloadBoxThumbnail(id: "bx_1")
            XCTFail("Expected 404")
        } catch HibossAPIError.requestFailed(let status, _) { XCTAssertEqual(status, 404) }
    }

    func testUploadThumbnailPutsRawJPEGAndDecodesItem() async throws {
        let item = try await api { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/box/items/bx_1/thumbnail")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(try Self.body(of: request), self.jpeg)
            return (200, Self.json(hasThumbnail: true))
        }.uploadBoxThumbnail(id: "bx_1", data: jpeg, contentType: "image/jpeg")
        XCTAssertTrue(item.hasThumbnail)
    }

    func testCreateSendsThumbnailPartAfterFileOnlyWhenPresent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("photo.png")
        let thumb = directory.appendingPathComponent("thumb.jpg")
        try Data("original bytes".utf8).write(to: file)
        try jpeg.write(to: thumb)
        for withThumbnail in [true, false] {
            let upload = BoxUpload(media: .init(fileURL: file, contentType: "image/png"),
                                   thumbnail: withThumbnail ? .init(fileURL: thumb, contentType: "image/jpeg") : nil)
            let item = try await api { request in
                let body = String(decoding: try Self.body(of: request), as: UTF8.self)
                XCTAssertTrue(body.contains("name=\"file\"; filename=\"photo.png\"\r\nContent-Type: image/png"))
                XCTAssertTrue(body.contains("original bytes"))
                let part = "name=\"thumbnail\"; filename=\"thumb.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"
                XCTAssertEqual(body.contains(part), withThumbnail)
                if withThumbnail {
                    let file = try XCTUnwrap(body.range(of: "name=\"file\""))
                    XCTAssertLessThan(file.lowerBound, try XCTUnwrap(body.range(of: part)).lowerBound)
                }
                XCTAssertFalse(body.contains("\"thumbnail\":"))
                return (201, Self.json(hasThumbnail: withThumbnail))
            }.createBoxItem(upload, idempotencyKey: "key", progress: { _ in })
            XCTAssertEqual(item.hasThumbnail, withThumbnail)
        }
    }

    private static func json(hasThumbnail: Bool) -> Data {
        Data((itemJSON.dropLast() + #","has_thumbnail":\#(hasThumbnail)}"#).utf8)
    }

    private static func body(of request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? HibossAPIError.invalidResponse }
            if count == 0 { return data }
            data.append(buffer, count: count)
        }
    }

    private func api(_ handler: @escaping (URLRequest) throws -> (Int, Data)) throws -> HibossAPI {
        BoxThumbnailURLProtocol.handler = { request in
            let (status, data) = try handler(request)
            let url = try XCTUnwrap(request.url)
            return (try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                                  headerFields: nil)), data)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BoxThumbnailURLProtocol.self]
        return HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "test-token"
        ), session: URLSession(configuration: config))
    }
}

private final class BoxThumbnailURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
