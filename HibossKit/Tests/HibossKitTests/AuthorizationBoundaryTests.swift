// Verifies typed history rejection and shared account clearing across transcript and device requests.
// Exports AuthorizationBoundaryTests; controllable reads and streams model rejected credentials.
// Dependencies: XCTest, Combine and HibossKit account stores.

import Combine
import XCTest
@testable import HibossKit

@MainActor
final class AuthorizationBoundaryTests: XCTestCase {
    override func tearDown() async throws {
        AccountAuthorization.shared.connect(nil)
        try await super.tearDown()
    }

    func testHistorySurfacesTypedAuthorizationAndStopsRetrying() async {
        let api = RejectedHistoryAPI(status: 401)
        var rejection: HistorySyncError?
        let sync = HistorySync(api: api) { _, error in rejection = error }
        await sync.synchronize()
        guard case let .authorization(error) = rejection else {
            XCTFail("Expected typed authorization failure")
            return
        }
        XCTAssertTrue(error.isAuthFailure)
        await sync.synchronize()
        let reads = await api.reads
        XCTAssertEqual(reads, 1)
        await sync.stop()
    }

    func testTranscriptReadRejectionClearsPreviouslyLoadedEventsAndOtherStores() async {
        let api = AuthorizationSessionAPI()
        let transcript = SessionStreamStore(sessionID: "session", pageSize: 1)
        let joined = StubJoinService(lists: [[JoinRequestsModelTests.mini]])
        let requests = JoinRequestsModel { joined }
        await requests.refresh()
        transcript.start(api: api)
        await waitForLoad(transcript)
        XCTAssertTrue(transcript.didLoad)
        await api.rejectReads(401)
        await transcript.refresh()
        XCTAssertTrue(transcript.events.isEmpty)
        XCTAssertFalse(transcript.didLoad)
        XCTAssertFalse(transcript.hasEarlier)
        XCTAssertTrue(requests.requests.isEmpty)
        XCTAssertFalse(requests.didLoad)
        transcript.stop()
    }

    func testTranscriptStreamRejectionClearsPreviouslyLoadedEvents() async {
        let api = AuthorizationSessionAPI()
        let transcript = SessionStreamStore(sessionID: "session")
        transcript.start(api: api)
        await waitForLoad(transcript)
        await api.rejectStream(401)
        let failure = expectation(description: "Stream authorization invalidates transcript")
        let observation = transcript.$didLoad.filter { !$0 }.prefix(1).sink { _ in failure.fulfill() }
        await fulfillment(of: [failure], timeout: 2)
        XCTAssertTrue(transcript.events.isEmpty)
        await transcript.refresh()
        XCTAssertFalse(transcript.didLoad, "Rejected API must no longer be usable")
        observation.cancel()
        transcript.stop()
    }

    func testJoinRequestRead401ClearsLoadedRequestsAndReview() async {
        let api = AuthorizationJoinAPI()
        let model = JoinRequestsModel { api }
        await model.refresh()
        let review = JoinRequestReview(requestID: JoinRequestsModelTests.mini.id, model: model)
        api.failure = 401
        await model.refresh()
        XCTAssertTrue(model.requests.isEmpty)
        XCTAssertFalse(model.didLoad)
        XCTAssertTrue(model.isForbidden)
        guard case .unavailable = review.phase else { XCTFail("Review retained account content"); return }
    }

    func testJoinRequestResetRetainsSharedAuthorizationRejection() async {
        let service = StubJoinService(lists: [[JoinRequestsModelTests.mini]])
        let model = JoinRequestsModel { service }

        XCTAssertTrue(AccountAuthorization.shared.reject(
            HibossAPIError.requestFailed(status: 401, message: "")
        ))
        model.reset()
        await model.refresh()

        XCTAssertEqual(service.listCalls, 0)
        XCTAssertTrue(model.isForbidden)
    }

    func testJoinRequestWrite401ClearsLoadedRequests() async {
        for approve in [true, false] {
            let api = AuthorizationJoinAPI()
            let model = JoinRequestsModel { api }
            await model.refresh()
            api.failure = 401
            if approve { _ = await model.approve(JoinRequestsModelTests.mini) }
            else { _ = await model.reject(JoinRequestsModelTests.mini) }
            XCTAssertTrue(model.requests.isEmpty)
            XCTAssertFalse(model.didLoad)
            XCTAssertTrue(model.isForbidden)
        }
    }

    func testTransientFailuresDoNotInvalidateTheAccount() {
        let boundary = AccountAuthorization()
        var cleared = 0
        let observation = boundary.observe { _ in cleared += 1 }
        XCTAssertFalse(boundary.reject(URLError(.timedOut)))
        XCTAssertFalse(boundary.reject(HibossAPIError.requestFailed(status: 503, message: "")))
        XCTAssertEqual(cleared, 0)
        XCTAssertTrue(boundary.reject(HibossAPIError.requestFailed(status: 401, message: "")))
        XCTAssertEqual(cleared, 1)
        observation.cancel()
    }

    private func waitForLoad(_ store: SessionStreamStore) async {
        let loaded = expectation(description: "Transcript loaded")
        let observation = store.$didLoad.filter { $0 }.prefix(1).sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 2)
        observation.cancel()
    }
}

private actor RejectedHistoryAPI: BossServing {
    let status: Int
    private(set) var reads = 0
    init(status: Int) { self.status = status }
    func fetchHistory() async throws -> [HistoryMessage] {
        reads += 1
        throw HibossAPIError.requestFailed(status: status, message: "")
    }
    func fetchMessage(_ id: MessageID) async throws -> MessageDetail { throw URLError(.badURL) }
    func reply(to id: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> { AsyncThrowingStream { $0.finish() } }
    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> { AsyncThrowingStream { $0.finish() } }
}

private actor AuthorizationSessionAPI: SessionStreamServing {
    private var status: Int?
    private var stream: AsyncThrowingStream<SessionStreamFrame, Error>.Continuation?
    private var streamWaiter: CheckedContinuation<Void, Never>?
    func rejectReads(_ status: Int) { self.status = status }
    func rejectStream(_ status: Int) async {
        if stream == nil { await withCheckedContinuation { streamWaiter = $0 } }
        stream?.finish(throwing: HibossAPIError.requestFailed(status: status, message: ""))
    }
    func fetchSessionEvents(sessionID: String, after: Int?, limit: Int) async throws -> SessionEventsPage {
        if let status { throw HibossAPIError.requestFailed(status: status, message: "") }
        return SessionEventsPage(events: [SessionEvent(
            id: "event", sessionId: sessionID, sequence: 2, kind: "message", createdAt: ""
        )])
    }
    func sessionEventStream(sessionID: String, after: Int) async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        let (result, continuation) = AsyncThrowingStream<SessionStreamFrame, Error>.makeStream()
        stream = continuation
        streamWaiter?.resume()
        streamWaiter = nil
        return result
    }
}

@MainActor
private final class AuthorizationJoinAPI: JoinRequestServing {
    var failure: Int?
    func check() throws {
        if let failure { throw HibossAPIError.requestFailed(status: failure, message: "") }
    }
    func listPendingJoinRequests() async throws -> [JoinRequest] {
        try check()
        return [JoinRequestsModelTests.mini]
    }
    func approveJoinRequest(id: String) async throws -> JoinApproval {
        try check()
        throw JoinRequestError.notFound
    }
    func rejectJoinRequest(id: String) async throws { try check() }
}
