// Proves a 403 denies one action for a valid account and never signs that account out.
// Exports PermissionDeniedTests over response validation, history sync and device requests.
// Dependencies: XCTest, HibossKit stores, AccountAuthorization; no live server.

import XCTest
@testable import HibossKit

@MainActor
final class PermissionDeniedTests: XCTestCase {
    override func tearDown() async throws {
        AccountAuthorization.shared.connect(nil)
        try await super.tearDown()
    }

    func testForbiddenResponseKeepsTheAccountAndExplainsThePermission() async throws {
        let boundary = AccountAuthorization()
        XCTAssertTrue(boundary.reject(HibossAPIError.requestFailed(status: 401, message: "")))
        XCTAssertFalse(AccountAuthorization().reject(HibossAPIError.requestFailed(status: 403, message: "")))
        let account = ConnectionConfig(serverURL: try XCTUnwrap(URL(string: "https://unit.test")),
                                       bossToken: "unit-token")
        AccountAuthorization.shared.connect(account)
        var cleared = 0
        let observation = AccountAuthorization.shared.observe { _ in cleared += 1 }
        defer { observation.cancel() }
        let response = try XCTUnwrap(HTTPURLResponse(url: account.serverURL, statusCode: 403,
                                                    httpVersion: nil, headerFields: nil))
        do {
            try await HibossAPI(config: account).validate(response)
            XCTFail("Expected a permission error")
        } catch {
            let failure = try XCTUnwrap(error as? HibossAPIError)
            XCTAssertFalse(failure.isAuthFailure)
            XCTAssertEqual(failure.errorDescription, kitL("You don't have permission to do that."))
        }
        XCTAssertFalse(AccountAuthorization.isRejected(JoinRequestError.forbidden))
        XCTAssertFalse(AccountAuthorization.shared.hasRejectedAccount)
        XCTAssertEqual(cleared, 0, "A permission error must not clear account content")
    }

    func testForbiddenHistoryReadIsAnOrdinaryRetryableFailure() async {
        let api = ForbiddenHistoryAPI()
        var outcome: HistorySyncError?
        let sync = HistorySync(api: api) { _, error in outcome = error }
        await sync.synchronize()
        guard case .failed = outcome else { return XCTFail("Expected an ordinary failure, got \(String(describing: outcome))") }
        await sync.synchronize()
        let reads = await api.reads
        XCTAssertEqual(reads, 2, "A permission error must not stop history sync")
        await sync.stop()
    }

    func testForbiddenDeviceRequestListKeepsTheAccountAndOtherContent() async {
        let other = JoinRequestsModel { StubJoinService(lists: [[JoinRequestsModelTests.mini]]) }
        await other.refresh()
        XCTAssertEqual(other.requests, [JoinRequestsModelTests.mini])
        let denied = JoinRequestsModel { StubJoinService(lists: [], listError: JoinRequestError.forbidden) }
        await denied.refresh()
        XCTAssertTrue(denied.isForbidden)
        XCTAssertFalse(AccountAuthorization.shared.hasRejectedAccount)
        XCTAssertEqual(other.requests, [JoinRequestsModelTests.mini], "Other screens keep their content")
    }

    func testForbiddenDecisionKeepsTheAccountAndShowsThePermissionMessage() async {
        let other = JoinRequestsModel { StubJoinService(lists: [[JoinRequestsModelTests.lab]]) }
        await other.refresh()
        let service = StubJoinService(lists: [[JoinRequestsModelTests.mini]])
        service.decisionError = JoinRequestError.forbidden
        let model = JoinRequestsModel { service }
        await model.refresh()
        let result = await model.approve(JoinRequestsModelTests.mini)
        XCTAssertEqual(result, .failed(kitL("Only an admin can approve devices")))
        XCTAssertTrue(model.isForbidden)
        XCTAssertTrue(model.requests.isEmpty)
        XCTAssertFalse(AccountAuthorization.shared.hasRejectedAccount)
        XCTAssertEqual(other.requests, [JoinRequestsModelTests.lab], "Other screens keep their content")
    }

    func testExplicitRefreshAfterForbiddenAsksTheServerAgain() async {
        let service = StubJoinService(lists: [[JoinRequestsModelTests.mini]], listError: JoinRequestError.forbidden)
        let model = JoinRequestsModel { service }
        await model.refresh()
        XCTAssertTrue(model.isForbidden)
        service.listError = nil
        await model.refresh()
        XCTAssertEqual(service.listCalls, 2, "A role granted later is picked up by the next refresh")
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.requests, [JoinRequestsModelTests.mini])
    }
}

private actor ForbiddenHistoryAPI: BossServing {
    private(set) var reads = 0
    func fetchHistory() async throws -> [HistoryMessage] {
        reads += 1
        throw HibossAPIError.requestFailed(status: 403, message: "")
    }
    func fetchMessage(_ id: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to id: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { $0.finish() } }
}
