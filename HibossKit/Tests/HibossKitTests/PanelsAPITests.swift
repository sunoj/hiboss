// Coverage for the boss panel list/detail endpoints and typed JSON values.
// Exports: PanelsAPITests verifying paths, authorization, and wire decoding.
// Dependencies: XCTest, Foundation URLProtocol, and HibossKit panel contracts.

import Foundation
import XCTest
@testable import HibossKit

final class PanelsAPITests: XCTestCase {
    override func tearDown() {
        PanelsURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchPanelsDecodesListShape() async throws {
        PanelsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/panels")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(for: request, json: #"{"panels":[{"panelId":"panel_1","agentId":"agent_1","agentName":"Build Agent","targetBossId":"boss_1","taskKey":"build","sessionId":"session_1","sessionLabel":"checkout/main","title":"Build","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"summary":{"stage":"Running"},"createdAt":"2026-09-07T10:00:00Z"}],"nextCursor":null}"#)
        }
        let panels = try await HibossAPI(config: config(), session: session()).fetchPanels()

        XCTAssertEqual(panels.count, 1)
        XCTAssertEqual(panels[0].id, "panel_1")
        XCTAssertEqual(panels[0].agentName, "Build Agent")
        XCTAssertEqual(panels[0].sessionLabel, "checkout/main")
        XCTAssertEqual(panels[0].summary, .object(["stage": .string("Running")]))
    }

    func testFetchPanelDecodesFlattenedMetadataAndDefinition() async throws {
        PanelsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/panels/panel_1")
            return try Self.response(for: request, json: #"{"panelId":"panel_1","agentId":"agent_1","agentName":"Build Agent","targetBossId":"boss_1","taskKey":"build","sessionId":"session_1","sessionLabel":"checkout/main","title":"Build","catalogId":"hiboss.panel","catalogVersion":1,"definitionRevision":1,"metadataVersion":1,"summary":{"stage":"Running"},"createdAt":"2026-09-07T10:00:00Z","definition":{"definitionRevision":1,"protocolVersion":1,"catalogId":"hiboss.panel","catalogVersion":1,"spec":{"root":"main","elements":{"main":{"type":"Stack","props":{"direction":"vertical"},"children":["metric"]},"metric":{"type":"Metric","props":{"label":"Completed","value":{"$state":"/task/completed"}},"children":[]}}},"stateSchema":{"type":"object"},"initialState":{"task":{"completed":4}},"createdAt":"2026-09-07T10:00:00Z"}}"#)
        }
        let detail = try await HibossAPI(config: config(), session: session()).fetchPanel("panel_1")

        XCTAssertEqual(detail.metadata.title, "Build")
        XCTAssertEqual(detail.metadata.agentName, "Build Agent")
        XCTAssertEqual(detail.metadata.sessionLabel, "checkout/main")
        XCTAssertEqual(detail.definition.spec.root, "main")
        XCTAssertEqual(detail.definition.spec.elements["metric"]?.type, "Metric")
        XCTAssertEqual(detail.definition.initialState, .object(["task": .object(["completed": .number(4)])]))
    }

    func testIssuesSingleUseSubscriberTicket() async throws {
        PanelsURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/panel-connections")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return try Self.response(for: request, json: #"{"ticket":"ticket-1","roomId":"boss-1","panelId":"panel-1","expiresAt":1788782400000}"#)
        }

        let ticket = try await HibossAPI(config: config(), session: session()).issuePanelConnectionTicket(panelID: "panel-1")

        XCTAssertEqual(ticket.ticket, "ticket-1")
        XCTAssertEqual(ticket.roomID, "boss-1")
        XCTAssertEqual(ticket.panelID, "panel-1")
    }

    private func config() throws -> ConnectionConfig {
        ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), bossToken: "test-token")
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PanelsURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, json: String) throws -> (HTTPURLResponse, Data) {
        let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
        return (response, Data(json.utf8))
    }
}

private final class PanelsURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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

extension PanelsAPITests {
    /// Pins the base path. Reusing the boss-scoped apiURL asked for /api/panels,
    /// which the server does not serve; it fell through to boss auth and reported the
    /// token as rejected, so the symptom pointed at credentials rather than the URL.
    func testPanelsAreRequestedUnderApiAndNotUnderApiBoss() throws {
        let api = HibossAPI(config: .init(
            serverURL: try XCTUnwrap(URL(string: "https://example.test")),
            bossToken: "hb_boss_test"
        ))
        let url = api.panelsURL.absoluteString
        XCTAssertEqual(url, "https://example.test/api/panels")
        XCTAssertFalse(url.contains("/api/boss/"), "panels must not be requested under the boss scope: \(url)")
    }
}
