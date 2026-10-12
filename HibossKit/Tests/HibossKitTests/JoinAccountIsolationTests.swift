// Holds join-request operations across account resets and task cancellation.
// Exports JoinAccountIsolationTests and a deterministic service barrier.
// Dependencies: XCTest and the shared join-request model and review state.

import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class JoinAccountIsolationTests: XCTestCase {
    func testLateRefreshDoesNotRestoreRequestsOrAnnounceAfterReset() async {
        let started = expectation(description: "old list started")
        let service = HeldJoinService(started: started)
        let model = JoinRequestsModel { service }
        var announcements = 0
        model.onNewRequests = { announcements += $0.count }
        let task = Task { await model.refresh() }
        await fulfillment(of: [started], timeout: 2)
        model.reset()
        await service.release()
        await task.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.requests.isEmpty)
        XCTAssertFalse(model.didLoad)
        XCTAssertEqual(announcements, 0)
    }

    func testLateForbiddenRefreshDoesNotReplaceNewAccountState() async {
        let started = expectation(description: "old list started")
        let service = HeldJoinService(started: started, error: .forbidden)
        var current: any JoinRequestServing = service
        let model = JoinRequestsModel { current }
        let task = Task { await model.refresh() }
        await fulfillment(of: [started], timeout: 2)
        model.reset()
        current = StubJoinService(lists: [[JoinRequestsModelTests.lab]])
        await model.refresh()
        await service.release()
        await task.value
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(model.requests, [JoinRequestsModelTests.lab])
    }

    func testReviewDropsLookupAfterAccountReset() async {
        let started = expectation(description: "lookup started")
        let service = HeldJoinService(started: started)
        let model = JoinRequestsModel { service }
        let review = JoinRequestReview(requestID: "jr-1", model: model)
        let task = Task { await review.load() }
        await fulfillment(of: [started], timeout: 2)
        model.reset()
        await service.release()
        await task.value
        XCTAssertEqual(review.phase, .loading)
    }

    func testReviewDropsCancelledLookup() async {
        let started = expectation(description: "lookup started")
        let service = HeldJoinService(started: started)
        let model = JoinRequestsModel { service }
        let review = JoinRequestReview(requestID: "jr-1", model: model)
        let task = Task { await review.load() }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await service.release()
        await task.value
        XCTAssertEqual(review.phase, .loading)
        XCTAssertTrue(model.requests.isEmpty)
    }

    func testReviewDropsApprovalAfterAccountReset() async {
        await assertDecisionIsDropped(approve: true, error: nil)
    }

    func testReviewDropsRejectionAfterAccountReset() async {
        await assertDecisionIsDropped(approve: false, error: nil)
    }

    func testReviewDropsDecisionFailureAfterAccountReset() async {
        await assertDecisionIsDropped(approve: true, error: .forbidden)
    }

    private func assertDecisionIsDropped(approve: Bool, error: JoinRequestError?) async {
        let started = expectation(description: "decision started")
        let service = HeldJoinService(started: started, holdList: false, error: error)
        let model = JoinRequestsModel { service }
        await model.refresh()
        let review = JoinRequestReview(requestID: "jr-1", model: model)
        let task = Task {
            if approve { await review.approve() } else { await review.reject() }
        }
        await fulfillment(of: [started], timeout: 2)
        model.reset()
        await service.release()
        await task.value
        XCTAssertEqual(review.phase, .ready(JoinRequestsModelTests.mini))
        XCTAssertNil(review.failureMessage)
        XCTAssertFalse(review.isDeciding)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.decidingID)
    }
}

private actor HeldJoinService: JoinRequestServing {
    let started: XCTestExpectation
    let holdList: Bool
    let error: JoinRequestError?
    private var gate: CheckedContinuation<Void, Never>?

    init(started: XCTestExpectation, holdList: Bool = true, error: JoinRequestError? = nil) {
        self.started = started
        self.holdList = holdList
        self.error = error
    }

    func release() {
        gate?.resume()
        gate = nil
    }

    private func hold() async throws {
        await withCheckedContinuation {
            gate = $0
            started.fulfill()
        }
        if let error { throw error }
    }

    func listPendingJoinRequests() async throws -> [JoinRequest] {
        if holdList { try await hold() }
        return [await JoinRequestsModelTests.mini]
    }

    func approveJoinRequest(id: String) async throws -> JoinApproval {
        try await hold()
        let json = #"{"id":"\#(id)","status":"approved","device_id":null,"agents":[]}"#
        return try JSONDecoder().decode(JoinApproval.self, from: Data(json.utf8))
    }

    func rejectJoinRequest(id: String) async throws { try await hold() }
}
