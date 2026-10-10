// Exercises real HTTP 409 replies against a lagging required-input list.
// Exports: DecisionConflictTests covering option and text-only decision closure.
// Dependencies: XCTest, HibossKit, native stores, and an isolated URLProtocol transport.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class DecisionConflictTests: XCTestCase {
    func testHTTPConflictClosesOnlyItsDecisionAndRefreshCannotReopenIt() async throws {
        for textOnly in [false, true] {
            let question = HistoryMessage(id: "closed", body: "Ship?", direction: "agent_to_boss",
                status: "delivered", priority: "normal", mode: textOnly ? "blocking" : "async",
                metadata: MessageMetadata(options: textOnly ? [] : ["Ship"]),
                createdAt: AttentionTestSupport.iso(.now), sessionId: "session")
            let other = AttentionTestSupport.ask(id: "other", options: ["Hold"])
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DecisionConflictProtocol.self]
            let client = HibossAPI(config: ConnectionConfig(
                serverURL: try XCTUnwrap(URL(string: textOnly
                    ? "https://decision-test.invalid" : "https://option-test.invalid")),
                bossToken: "synthetic-decision-token"), session: URLSession(configuration: configuration))
            let api = ConflictReplyAPI(client: client, messages: [question, other])
            let inputs = RequiredInputStore(reconnectDelay: .seconds(60))
            let list = ControlledRequiredInputs(messages: [question, other])
            let flow = OptionFlowStore(reconnectDelay: .seconds(60))
            let overview = OverviewStore()
            overview.bind(flow: flow, inputs: inputs)
            inputs.connect(list)
            flow.connect(api: api)
            defer {
                inputs.disconnect()
                flow.disconnect()
            }
            try await waitForCondition { inputs.state.coverageComplete && flow.historyState == .loaded }
            let reply = AttentionReplyState()
            reply.drafts[question.id] = "Ship after review"
            await reply.send(reply.drafts[question.id] ?? "", for: question.id) { text, id in
                await overview.answer(text, for: id, using: flow.answer)
            }
            XCTAssertEqual(reply.errors[question.id], .alreadyResolved)
            XCTAssertEqual(reply.errors[question.id]?.text, L("No longer open"))
            XCTAssertEqual(reply.errors[question.id]?.choiceText, L("No longer open"))
            XCTAssertEqual(reply.drafts[question.id], "Ship after review")
            XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .closed)
            XCTAssertFalse(overview.snapshot.answerability.permitsReply(to: question))
            XCTAssertEqual(overview.snapshot.today.decisions.map(\.id), [other.id])
            inputs.refresh()
            try await list.waitForFetch(count: 2)
            try await waitForCondition { !inputs.state.refreshing }
            XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .closed)
            XCTAssertEqual(overview.snapshot.answerability.state(for: other.id), .open)
        }
    }
}

private actor ConflictReplyAPI: BossServing {
    let client: HibossAPI
    let messages: [HistoryMessage]

    init(client: HibossAPI, messages: [HistoryMessage]) {
        self.client = client
        self.messages = messages
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func messageStream() -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { _ in } }
    func fetchHistory() async throws -> [HistoryMessage] { messages }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        try await client.reply(to: messageID, with: choice)
    }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        MessageDetail(message: messages[0], replies: [])
    }
}

private final class DecisionConflictProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 409, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]) else { return }
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(url.path, "/api/boss/messages/closed/reply")
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = url.host == "option-test.invalid" ? "option already resolved" : "decision no longer open"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
