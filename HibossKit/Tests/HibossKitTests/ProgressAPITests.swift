// Coverage for HibossAPI progress endpoints: feed, projects, and delete.
// Exports: ProgressAPITests verifying paths, query items, and decoding.
// Dependencies: XCTest, Foundation URLProtocol, and the HibossKit API client.

import Foundation
import XCTest
@testable import HibossKit

final class ProgressAPITests: XCTestCase {
    override func tearDown() {
        ProgressURLProtocol.handler = nil
        super.tearDown()
    }

    func testProgressFeedUsesQueryAndDecodesPage() async throws {
        ProgressURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/progress")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(items?.first { $0.name == "limit" }?.value, "20")
            XCTAssertEqual(items?.first { $0.name == "project" }?.value, "hiboss")
            XCTAssertEqual(items?.first { $0.name == "before" }?.value, "2026-08-14T09:00:00Z")
            return try Self.response(
                for: request,
                json: #"{"posts":[{"id":"p1","project":"hiboss","agent_id":"ak1","agent_name":"cli","body":"Hi","media":[],"tags":[],"created_at":"2026-08-14T08:00:00Z"}],"next_before":null}"#
            )
        }
        let api = HibossAPI(config: try config(), session: session())

        let page = try await api.progressFeed(project: "hiboss", limit: 20, before: "2026-08-14T09:00:00Z")

        XCTAssertEqual(page.posts.count, 1)
        XCTAssertEqual(page.posts.first?.id, "p1")
        XCTAssertNil(page.nextBefore)
    }

    func testProgressProjectsUsesAuthorizedEndpoint() async throws {
        ProgressURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/progress/projects")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(
                for: request,
                json: #"{"projects":[{"project":"hiboss","count":12,"last_post_at":"2026-08-14T09:00:00Z","agent_id":"ak1"}]}"#
            )
        }
        let api = HibossAPI(config: try config(), session: session())

        let projects = try await api.progressProjects()

        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.project, "hiboss")
        XCTAssertEqual(projects.first?.count, 12)
    }

    func testDeleteProgressPostUsesDelete() async throws {
        ProgressURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/progress/p1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(for: request, json: "{}")
        }
        let api = HibossAPI(config: try config(), session: session())

        try await api.deleteProgressPost(id: "p1")
    }

    private func config() throws -> ConnectionConfig {
        let serverURL = try XCTUnwrap(URL(string: "https://hiboss.example"))
        return ConnectionConfig(serverURL: serverURL, bossToken: "test-token")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgressURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        json: String
    ) throws -> (HTTPURLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        return (response, Data(json.utf8))
    }
}

private final class ProgressURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: HibossAPIError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
