// Covers the approval-sheet state machine: ID resolution, decisions, and failures.
// Exports: JoinRequestReviewTests.
// Dependencies: XCTest, HibossKit's JoinRequestReview, and StubJoinService.

import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class JoinRequestReviewTests: XCTestCase {
    func testUnknownIDResolvesThroughARefresh() async {
        let model = JoinRequestsModel { StubJoinService(lists: [[JoinRequestsModelTests.mini]]) }
        let review = JoinRequestReview(requestID: "jr-1", model: model)
        XCTAssertEqual(review.phase, .loading)

        await review.load()

        XCTAssertEqual(review.phase, .ready(JoinRequestsModelTests.mini))
    }

    func testProcessedRequestIsUnavailable() async {
        let model = JoinRequestsModel { StubJoinService(lists: [[]]) }
        let review = JoinRequestReview(requestID: "jr-1", model: model)

        await review.load()

        XCTAssertEqual(review.phase, .unavailable(kitL("This request is no longer pending.")))
    }

    func testForbiddenListShowsTheAdminMessage() async {
        let model = JoinRequestsModel { StubJoinService(lists: [], listError: JoinRequestError.forbidden) }
        let review = JoinRequestReview(requestID: "jr-1", model: model)

        await review.load()

        XCTAssertEqual(review.phase, .unavailable(kitL("Only an admin can approve devices")))
    }

    func testApproveAndRejectReachTheirOutcomes() async {
        let service = StubJoinService(lists: [[JoinRequestsModelTests.mini, JoinRequestsModelTests.lab]])
        let model = JoinRequestsModel { service }
        await model.refresh()
        let approve = JoinRequestReview(requestID: "jr-1", model: model)
        let reject = JoinRequestReview(requestID: "jr-2", model: model)

        await approve.approve()
        await reject.reject()

        guard case .approved(JoinRequestsModelTests.mini, _) = approve.phase else {
            return XCTFail("Expected approved, got \(approve.phase)")
        }
        XCTAssertEqual(reject.phase, .rejected(JoinRequestsModelTests.lab))
        XCTAssertEqual(service.approved, ["jr-1"])
    }

    func testStillPendingConflictKeepsTheSheetWithTheServerText() async {
        let service = StubJoinService(lists: [[JoinRequestsModelTests.mini]])
        service.decisionError = JoinRequestError.conflict("name mini-claude is taken")
        let model = JoinRequestsModel { service }
        await model.refresh()
        let review = JoinRequestReview(requestID: "jr-1", model: model)

        await review.approve()

        XCTAssertEqual(review.phase, .ready(JoinRequestsModelTests.mini))
        XCTAssertEqual(review.failureMessage, "name mini-claude is taken")
    }
}
