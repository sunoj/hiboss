// Verifies the browser through HibossKit's authenticated HTTP and native action boundaries.
// Exports: BoxBrowserAPITests with query, cursor, media, deletion and clipboard coverage.
// Dependencies: XCTest, URLProtocol and BoxBrowserActions; all credentials are synthetic.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class BoxBrowserAPITests: XCTestCase {
    func testKindSearchAndCursorReachAuthenticatedServer() async throws {
        let api = try client()
        let store = BoxBrowserStore { api }
        store.kind = .file
        store.query = "  review notes  "
        await store.refresh()
        XCTAssertNil(store.error)
        XCTAssertEqual(store.items.map(\.id), ["new"])
        XCTAssertEqual(store.nextCursor, "opaque cursor")
        await store.loadMore()
        XCTAssertNil(store.pageError)
        XCTAssertEqual(store.items.map(\.id), ["new", "old"])
        XCTAssertNil(store.nextCursor)
        store.kind = nil
        store.query = ""
        await store.refresh()
        XCTAssertEqual(store.items.map(\.id), ["all"])
    }

    func testAuthenticatedMediaIsSavedBeforeDefaultAppOpensAndAgentItemCanBeDeleted() async throws {
        let api = try client()
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        let item = BoxBrowserFixtures.items[3]
        var opened: URL?
        let copied = try await BoxBrowserActions.open(item, media: media) { file in
            opened = file
            XCTAssertTrue(file.isFileURL)
            XCTAssertEqual(file.lastPathComponent, "review-notes.pdf")
            XCTAssertEqual(try? Data(contentsOf: file), Data("synthetic document".utf8))
            return true
        }
        XCTAssertNil(copied)
        XCTAssertNotNil(opened)
        let store = BoxBrowserStore { api }
        await store.refresh()
        let deleted = await store.delete(BoxBrowserFixtures.items[0])
        XCTAssertTrue(deleted)
        XCTAssertNil(store.actionError)
    }

    func testLinkUsesBrowserAndTextCopiesWithNoMediaRead() async throws {
        let media = BoxBrowserMedia { nil }
        var opened: URL?
        _ = try await BoxBrowserActions.open(BoxBrowserFixtures.items[1], media: media) {
            opened = $0
            return true
        }
        XCTAssertEqual(opened?.absoluteString, "https://developer.apple.com/swiftui/")
        let text = try await BoxBrowserActions.open(BoxBrowserFixtures.items[2], media: media)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(BoxBrowserActions.copy(try XCTUnwrap(text), to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), BoxBrowserFixtures.items[2].text)
        XCTAssertTrue(media.files.isEmpty)
    }

    func testInvalidLinkAndRejectedOpenerProduceActionErrors() async {
        let media = BoxBrowserMedia { nil }
        let invalid = BoxBrowserFixtures.item("bad", kind: .link, url: "file:///tmp/example")
        do {
            _ = try await BoxBrowserActions.open(invalid, media: media) { _ in
                XCTFail("Non-web URL reached the browser")
                return true
            }
            XCTFail("Invalid link was accepted")
        } catch { XCTAssertNotNil(error as? BoxBrowserError) }
        do {
            _ = try await BoxBrowserActions.open(BoxBrowserFixtures.items[1], media: media) { _ in false }
            XCTFail("Rejected opening was accepted")
        } catch { XCTAssertNotNil(error as? BoxBrowserError) }
    }

    private func client() throws -> HibossAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BrowserURLProtocol.self]
        return HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://browser-test.invalid")),
            bossToken: "synthetic-browser-token"), session: URLSession(configuration: configuration))
    }
}

private final class BrowserURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                "Bearer synthetic-browser-token")
            let data: Data
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(url.path, "/api/box/items/image")
                XCTAssertNil(url.query, "Boss deletion must not purge media")
                data = Data()
            } else if url.path.hasSuffix("/media") {
                XCTAssertEqual(url.path, "/api/box/items/file/media")
                data = Data("synthetic document".utf8)
            } else { data = try page(url) }
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }

    private func page(_ url: URL) throws -> Data {
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["limit"], "20")
        let result: BoxPage
        if url.path.hasSuffix("/search") {
            XCTAssertEqual(values["q"], "review notes")
            XCTAssertEqual(values["kind"], "file")
            if let cursor = values["cursor"] {
                XCTAssertEqual(cursor, "opaque cursor")
                result = BoxPage(items: [BoxBrowserFixtures.item("old", kind: .file,
                    createdAt: "2026-10-08T08:00:00Z")])
            } else {
                result = BoxPage(items: [BoxBrowserFixtures.item("new", kind: .file)],
                    nextCursor: "opaque cursor")
            }
        } else {
            XCTAssertEqual(url.path, "/api/box/items")
            XCTAssertNil(values["q"])
            XCTAssertNil(values["kind"])
            result = BoxPage(items: [BoxBrowserFixtures.item("all")])
        }
        return try JSONEncoder().encode(result)
    }
}
