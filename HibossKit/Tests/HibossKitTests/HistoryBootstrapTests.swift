// Joins the full HTTP response contract to the native stream-driven delta fetch.
// Exports HistoryBootstrapTests; uses HibossAPI with a synthetic URLProtocol transport.
// Depends on OptionFlowStore and deterministic stream events, with no network access.

import Combine
import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class HistoryBootstrapTests: XCTestCase {
    func testFullFetchThenStreamEventSendsTheFullResponseCursor() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BootstrapURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = HibossAPI(config: ConnectionConfig(
            serverURL: URL(string: "https://bootstrap.test")!, bossToken: "synthetic"
        ), session: session)
        let events = HistoryTestAPI([])
        let flow = OptionFlowStore()
        let loaded = expectation(description: "full page loaded")
        let observation = flow.$historyState.sink { state in
            if state == .loaded { loaded.fulfill() }
        }
        let delta = expectation(description: "stream event sends updated_after")
        BootstrapURLProtocol.delta = delta
        defer {
            observation.cancel()
            flow.disconnect()
            BootstrapURLProtocol.delta = nil
        }
        flow.connect(api: BootstrapHistoryAPI(transport: transport, events: events))
        await fulfillment(of: [loaded], timeout: 2)
        observation.cancel()
        await events.sendEvent()
        await fulfillment(of: [delta], timeout: 2)
        await flow.refreshHistory()
    }

    func testFullResponseCursorIsRetainedInMemoryForTheNextFetch() async throws {
        let full = try JSONDecoder().decode(HistoryResponse.self, from: BootstrapURLProtocol.full)
        XCTAssertNil(full.hasMore)
        let api = HistoryTestAPI([full])
        let sync = HistorySync(api: api) { _, _ in }
        await sync.synchronize()
        await sync.synchronize()
        await sync.stop()
        let cursors = await api.cursors
        XCTAssertEqual(cursors, [nil, BootstrapURLProtocol.cursor])
    }

}

private struct BootstrapHistoryAPI: BossServing {
    let transport: HibossAPI
    let events: HistoryTestAPI
    func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        try await transport.fetchHistoryPage(updatedAfter: updatedAfter)
    }
    func fetchHistory() async throws -> [HistoryMessage] { [] }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { await events.messageStream() }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { _ in } }
    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}

private final class BootstrapURLProtocol: URLProtocol, @unchecked Sendable {
    static let cursor = "2026-10-10 10:20:30"
    static let full = Data(#"{"messages":[],"total":0,"cursor":"2026-10-10 10:20:30"}"#.utf8)
    nonisolated(unsafe) static var delta: XCTestExpectation?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
        let cursor = items?.first { $0.name == "updated_after" }?.value
        XCTAssertEqual(request.url?.path, "/api/boss/messages")
        if let cursor {
            XCTAssertEqual(cursor, Self.cursor)
            Self.delta?.fulfill()
        }
        guard let url = request.url, let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: nil
        ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payload = cursor == nil ? Self.full : Data(
            #"{"messages":[],"total":0,"cursor":"2026-10-10 10:20:30","has_more":false}"#.utf8
        )
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
