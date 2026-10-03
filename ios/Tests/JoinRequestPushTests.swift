// Covers the join-request push: category without actions and payload → approval sheet routing.
// Exports: JoinRequestPushTests.
// Dependencies: XCTest, UserNotifications, HibossKit join requests, and the HiBoss app target.

import Foundation
import HibossKit
import UserNotifications
import XCTest
@testable import HiBoss

@MainActor
final class JoinRequestPushTests: XCTestCase {
    private let payload: [AnyHashable: Any] = [
        "aps": ["alert": ["title": "New device wants to join", "body": "mini (claude, codex) · code 012345"],
                "category": "HIBOSS_JOIN_REQUEST"],
        "join_request_id": "jr-1",
    ]

    override func tearDown() async throws {
        _ = AppRouter.shared.takeJoinRequest()
    }

    func testCategoryOffersNoActionsBecauseTheCodeMustBeComparedFirst() {
        let category = JoinRequestPush.notificationCategory()
        XCTAssertEqual(category.identifier, "HIBOSS_JOIN_REQUEST")
        XCTAssertEqual(PushCategory.joinRequest, "HIBOSS_JOIN_REQUEST")
        XCTAssertTrue(category.actions.isEmpty)
    }

    func testTapRoutesToTheRequestAndOtherResponsesDoNot() {
        XCTAssertEqual(
            JoinRequestPush.requestID(userInfo: payload, actionIdentifier: UNNotificationDefaultActionIdentifier),
            "jr-1"
        )
        XCTAssertNil(JoinRequestPush.requestID(userInfo: payload, actionIdentifier: UNNotificationDismissActionIdentifier))
        XCTAssertNil(JoinRequestPush.requestID(
            userInfo: ["messageId": "m-1"], actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        XCTAssertNil(JoinRequestPush.requestID(
            userInfo: ["join_request_id": "  "], actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
    }

    func testRoutedIDOpensTheSheetOnTheMatchingRequestOnce() async throws {
        let id = try XCTUnwrap(JoinRequestPush.requestID(
            userInfo: payload, actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        AppRouter.shared.openJoinRequest(id: id)

        let target = try XCTUnwrap(AppRouter.shared.takeJoinRequest())
        XCTAssertNil(AppRouter.shared.takeJoinRequest(), "a tap opens the sheet once")

        let request = JoinRequest(id: "jr-1", deviceLabel: "mini", verificationCode: "012345")
        let model = JoinRequestsModel { OneListService(requests: [request]) }
        let review = JoinRequestReview(requestID: target.id, model: model)
        await review.load()
        XCTAssertEqual(review.phase, .ready(request))
    }

    func testForbiddenListShowsTheAdminMessage() async {
        let model = JoinRequestsModel { OneListService(requests: [], error: JoinRequestError.forbidden) }
        await model.refresh()
        XCTAssertTrue(model.isForbidden)
        XCTAssertEqual(JoinRequestError.forbidden.localizedDescription, "Only an admin can approve devices")
    }
}

private struct OneListService: JoinRequestServing {
    let requests: [JoinRequest]
    var error: JoinRequestError?

    func listPendingJoinRequests() async throws -> [JoinRequest] {
        if let error { throw error }
        return requests
    }

    func approveJoinRequest(id: String) async throws -> JoinApproval { throw JoinRequestError.notFound }
    func rejectJoinRequest(id: String) async throws { throw JoinRequestError.notFound }
}
