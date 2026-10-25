// Flow coverage for the shared join-request model: dedupe, admin gating, lookup, and decisions.
// Exports: JoinRequestsModelTests and StubJoinService.
// Dependencies: XCTest and HibossKit's JoinRequestsModel.

import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class JoinRequestsModelTests: XCTestCase {
    override func tearDown() async throws {
        AccountAuthorization.shared.connect(nil)
        try await super.tearDown()
    }

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

    func testEqualAccountReconnectRestartsPollingAndAllowsImmediateLookup() async throws {
        let account = ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://unit.test")), bossToken: "unit-token"
        )
        let pollService = CountingJoinService(request: Self.mini)
        let lookupService = CountingJoinService(request: Self.mini)
        let pollModel = JoinRequestsModel(pollInterval: .milliseconds(5)) { pollService }
        let lookupModel = JoinRequestsModel { lookupService }
        AccountAuthorization.shared.connect(account)

        XCTAssertTrue(AccountAuthorization.shared.reject(
            HibossAPIError.requestFailed(status: 401, message: "")
        ))
        AccountAuthorization.shared.connect(account)

        let secondRead = expectation(description: "poll continues after the first read")
        var didFulfillSecondRead = false
        pollService.onRead = {
            if pollService.listCalls >= 2, !didFulfillSecondRead {
                didFulfillSecondRead = true
                secondRead.fulfill()
            }
        }
        let polling = Task { await pollModel.poll() }
        let lookup = await lookupModel.lookup(id: Self.mini.id)

        XCTAssertEqual(lookup, .found(Self.mini))
        await fulfillment(of: [secondRead], timeout: 1)
        XCTAssertGreaterThanOrEqual(pollService.listCalls, 2)
        XCTAssertNotEqual(pollModel.state, .forbidden)
        polling.cancel()
        await polling.value
    }

    func testApproveRemovesTheRequest() async throws {
        let service = StubJoinService(lists: [[Self.mini]])
        let model = JoinRequestsModel { service }
        await model.refresh()

        let result = await model.approve(Self.mini)

        guard case let .approved(approval) = result else {
            return XCTFail("Expected approval, got \(result)")
        }
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

    func testFailedFirstReadKeepsItsResultDuringRetry() async {
        let service = HeldFailedJoinRead()
        let model = JoinRequestsModel { service }
        await model.refresh()
        let previous = model.state
        XCTAssertFalse(model.didLoad)
        await service.holdNext()
        let retry = Task { await model.refresh() }
        await service.waitForRead()
        XCTAssertEqual(model.state, previous)
        await service.release()
        await retry.value
    }

    func testLookupWaitsForTheInitialInventoryRead() async {
        let service = HeldFailedJoinRead()
        await service.holdNext()
        let model = JoinRequestsModel { service }
        let refresh = Task { await model.refresh() }
        await service.waitForRead()
        var outcome: JoinRequestLookup?
        let lookup = Task { outcome = await model.lookup(id: Self.mini.id) }
        let pending = expectation(description: "lookup waits for inventory")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pending.fulfill() }
        await fulfillment(of: [pending], timeout: 2)
        XCTAssertNil(outcome)
        await service.release(returning: [Self.mini])
        await refresh.value
        await lookup.value
        XCTAssertEqual(outcome, .found(Self.mini))
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
    var listError: Error?
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

@MainActor
private final class CountingJoinService: JoinRequestServing {
    let request: JoinRequest
    private(set) var listCalls = 0
    var onRead: (() -> Void)?

    init(request: JoinRequest) {
        self.request = request
    }

    func listPendingJoinRequests() async throws -> [JoinRequest] {
        listCalls += 1
        onRead?()
        return [request]
    }

    func approveJoinRequest(id: String) async throws -> JoinApproval {
        throw JoinRequestError.notFound
    }

    func rejectJoinRequest(id: String) async throws {}
}

private actor HeldFailedJoinRead: JoinRequestServing {
    private var hold = false
    private var read: CheckedContinuation<[JoinRequest], Error>?
    private var waiter: CheckedContinuation<Void, Never>?

    func holdNext() { hold = true }
    func waitForRead() async {
        if read != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        read?.resume(throwing: URLError(.notConnectedToInternet))
        read = nil
    }
    func release(returning requests: [JoinRequest]) {
        read?.resume(returning: requests)
        read = nil
    }
    func listPendingJoinRequests() async throws -> [JoinRequest] {
        if !hold { throw URLError(.notConnectedToInternet) }
        return try await withCheckedThrowingContinuation {
            read = $0
            waiter?.resume()
            waiter = nil
        }
    }
    func approveJoinRequest(id: String) async throws -> JoinApproval { throw JoinRequestError.forbidden }
    func rejectJoinRequest(id: String) async throws { throw JoinRequestError.forbidden }
}
