// Flow coverage for the shared join-request model: dedupe, admin gating, lookup, and decisions.
// Exports: JoinRequestsModelTests and StubJoinService.
// Dependencies: XCTest and HibossKit's JoinRequestsModel.

import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class JoinRequestsModelTests: XCTestCase {
    func testNewRequestsAreAnnouncedOncePerID() async {
        let service = StubJoinService(lists: [[Self.mini], [Self.mini], [Self.mini, Self.lab]])
        let model = JoinRequestsModel { service }
        var announced: [String] = []
        model.onNewRequests = { announced += $0.map(\.id) }

        await model.refresh()
        await model.refresh()
        model.reset()
        await model.refresh()

        XCTAssertEqual(announced, ["jr-1", "jr-2"])
        XCTAssertEqual(model.pendingCount, 2)
    }

    func testForbiddenStopsPolling() async {
        let service = StubJoinService(lists: [], listError: JoinRequestError.forbidden)
        let model = JoinRequestsModel(pollInterval: .milliseconds(1)) { service }

        await model.poll()

        XCTAssertEqual(model.state, .forbidden)
        XCTAssertEqual(service.listCalls, 1, "a 403 must not be retried by the poller")
    }

    func testLookupRefreshesAndReportsMissingRequests() async {
        let service = StubJoinService(lists: [[Self.mini], [Self.mini]])
        let model = JoinRequestsModel { service }

        let found = await model.lookup(id: "jr-1")
        let missing = await model.lookup(id: "gone")

        XCTAssertEqual(found, .found(Self.mini))
        XCTAssertEqual(missing, .notPending)
    }

    func testApproveRemovesTheRequest() async throws {
        let service = StubJoinService(lists: [[Self.mini]])
        let model = JoinRequestsModel { service }
        await model.refresh()

        let result = await model.approve(Self.mini)

        guard case let .approved(approval) = result else { return XCTFail("Expected approval, got \(result)") }
        XCTAssertEqual(approval.id, "jr-1")
        XCTAssertEqual(service.approved, ["jr-1"])
        XCTAssertTrue(model.requests.isEmpty)
    }

    func testRequestWithoutCodeIsNeverSentForApproval() async {
        let service = StubJoinService(lists: [])
        let model = JoinRequestsModel { service }
        let noCode = JoinRequest(id: "jr-3", deviceLabel: "lab", verificationCode: nil)

        let result = await model.approve(noCode)

        guard case .failed = result else { return XCTFail("Expected failure") }
        XCTAssertTrue(service.approved.isEmpty)
    }

    func testConflictReportsTheServerTextAndRefreshes() async {
        let service = StubJoinService(lists: [[Self.mini], []])
        service.decisionError = JoinRequestError.conflict("already approved")
        let model = JoinRequestsModel { service }
        await model.refresh()

        let result = await model.reject(Self.mini)

        XCTAssertEqual(result, .failed("already approved"))
        XCTAssertEqual(service.listCalls, 2)
        XCTAssertTrue(model.requests.isEmpty)
    }

    func testForbiddenDecisionMarksTheModelForbidden() async {
        let service = StubJoinService(lists: [[Self.mini]])
        service.decisionError = JoinRequestError.forbidden
        let model = JoinRequestsModel { service }
        await model.refresh()

        let result = await model.approve(Self.mini)

        XCTAssertEqual(result, .failed(kitL("Only an admin can approve devices")))
        XCTAssertTrue(model.isForbidden)
    }

    func testMissingConnectionStaysIdle() async {
        let model = JoinRequestsModel { nil }
        await model.refresh()
        XCTAssertEqual(model.state, .idle)
    }

    static let mini = JoinRequest(
        id: "jr-1", deviceLabel: "mini", deviceHost: "mini.local", inviterLabel: "Office Mac",
        verificationCode: "012345", profiles: [JoinRequestProfile(profile: "claude", name: "mini-claude")]
    )
    static let lab = JoinRequest(id: "jr-2", deviceLabel: "lab", verificationCode: "999000")
}

final class StubJoinService: JoinRequestServing, @unchecked Sendable {
    private var lists: [[JoinRequest]]
    let listError: Error?
    var decisionError: Error?
    private(set) var listCalls = 0
    private(set) var approved: [String] = []

    init(lists: [[JoinRequest]], listError: Error? = nil) {
        self.lists = lists
        self.listError = listError
    }

    func listPendingJoinRequests() async throws -> [JoinRequest] {
        listCalls += 1
        if let listError { throw listError }
        return lists.count > 1 ? lists.removeFirst() : (lists.first ?? [])
    }

    func approveJoinRequest(id: String) async throws -> JoinApproval {
        if let decisionError { throw decisionError }
        approved.append(id)
        let json = #"{"id":"\#(id)","status":"approved","device_id":null,"agents":[]}"#
        return try JSONDecoder().decode(JoinApproval.self, from: Data(json.utf8))
    }

    func rejectJoinRequest(id: String) async throws {
        if let decisionError { throw decisionError }
    }
}
