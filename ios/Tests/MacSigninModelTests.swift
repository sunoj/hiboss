// Covers signing a Mac in from this iPhone: scan admission, review, approve, reject and their errors.
// Exports: MacSigninModelTests.
// Dependencies: XCTest, HibossKit sign-in types, and the HiBoss app target.

import Foundation
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class MacSigninModelTests: XCTestCase {
    private let server = URL(string: "https://hiboss.example")!
    private let requestID = String(repeating: "ab", count: 16)

    private func link(server: String = "https://hiboss.example") -> String {
        let encoded = server.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? server
        return "hiboss://signin?server=\(encoded)&request=\(requestID)"
    }

    private func reviewing(_ api: FakeSigninAPI) async -> MacSigninModel {
        let model = MacSigninModel(serverURL: server, api: api)
        XCTAssertEqual(model.accept(scanned: link()), .accepted)
        await model.load()
        return model
    }

    func testApproveShowsTheCodeForThatRequest() async throws {
        let api = FakeSigninAPI()
        let model = await reviewing(api)
        guard case let .review(summary) = model.phase else { return XCTFail("\(model.phase)") }
        XCTAssertEqual(summary.deviceLabel, "Studio Mac")
        XCTAssertEqual(summary.origin, "NL · Amsterdam")

        await model.approve()

        let expiry = try XCTUnwrap(ISODate.parse("2026-10-04T12:10:00.000Z"))
        XCTAssertEqual(model.phase, .approved(MacSigninCode(code: "306142", deviceLabel: "Studio Mac", expiresAt: expiry)))
        XCTAssertEqual(api.calls, ["get \(requestID)", "approve \(requestID)"])
        XCTAssertFalse(model.isDeciding)
    }

    func testForbiddenReviewSaysOnlyAnAdminOrManagerCanSignInAMac() async {
        let model = await reviewing(FakeSigninAPI(getStatus: 403))
        XCTAssertEqual(model.phase, .failed(.forbidden))
        XCTAssertEqual(MacSigninFailure.forbidden.message, "Only an admin or manager can sign in a Mac.")
    }

    func testForbiddenApprovalIsTheRoleMessageToo() async {
        let model = await reviewing(FakeSigninAPI(approveStatus: 403))
        await model.approve()
        XCTAssertEqual(model.phase, .failed(.forbidden))
    }

    func testConflictOnApprovalSaysTheRequestWasAlreadyHandled() async {
        let model = await reviewing(FakeSigninAPI(approveStatus: 409))
        await model.approve()
        XCTAssertEqual(model.phase, .failed(.alreadyHandled))
        XCTAssertEqual(MacSigninFailure.alreadyHandled.message, "This request was already handled.")
    }

    func testLinkForAnotherServerIsRefusedWithoutAnyRequest() async {
        let api = FakeSigninAPI()
        let model = MacSigninModel(serverURL: server, api: api)

        let outcome = model.accept(scanned: link(server: "https://evil.example"))

        XCTAssertEqual(outcome, .rejected("This Mac is signing in to a different server: evil.example"))
        XCTAssertEqual(model.scanRejection, "This Mac is signing in to a different server: evil.example")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.link)
        await model.load()
        XCTAssertEqual(api.calls, [], "nothing is sent for a server this iPhone is not signed in to")
    }

    func testNonSigninCodeIsRefused() {
        let model = MacSigninModel(serverURL: server, api: FakeSigninAPI())
        let pair = "hiboss://pair?server=https%3A%2F%2Fhiboss.example&code=hb_pair_" + String(repeating: "e", count: 64)
        XCTAssertEqual(model.accept(scanned: pair), .rejected("That QR code is not a HiBoss sign-in code."))
        XCTAssertEqual(model.phase, .idle)
    }

    func testWithoutAConnectionTheScanSaysToConnectFirst() {
        let model = MacSigninModel(serverURL: nil, api: nil)
        XCTAssertEqual(model.accept(scanned: link()), .accepted)
        XCTAssertEqual(model.phase, .failed(.notConfigured))
    }

    func testSameServerIgnoresCaseTrailingSlashAndDefaultPort() throws {
        func url(_ value: String) throws -> URL { try XCTUnwrap(URL(string: value)) }
        XCTAssertTrue(MacSigninModel.isSameServer(try url("https://HiBoss.example/"), try url("https://hiboss.example")))
        XCTAssertTrue(MacSigninModel.isSameServer(try url("https://hiboss.example:443"), try url("https://hiboss.example")))
        XCTAssertFalse(MacSigninModel.isSameServer(try url("https://hiboss.example:8443"), try url("https://hiboss.example")))
        XCTAssertFalse(MacSigninModel.isSameServer(try url("http://hiboss.example"), try url("https://hiboss.example")))
        XCTAssertFalse(MacSigninModel.isSameServer(try url("https://hiboss.example/a"), try url("https://hiboss.example")))
    }

    func testRejectEndsTheRequest() async {
        let api = FakeSigninAPI()
        let model = await reviewing(api)
        await model.reject()
        XCTAssertEqual(model.phase, .rejected(deviceLabel: "Studio Mac"))
        XCTAssertEqual(api.calls, ["get \(requestID)", "reject \(requestID)"])
    }

    func testRejectConflictSaysTheRequestWasAlreadyHandled() async {
        let model = await reviewing(FakeSigninAPI(rejectStatus: 409))
        await model.reject()
        XCTAssertEqual(model.phase, .failed(.alreadyHandled))
    }

    func testResetDropsTheCodeAndTheRequest() async {
        let model = await reviewing(FakeSigninAPI())
        await model.approve()
        model.reset()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.link)
    }

    func testFailureMapping() {
        XCTAssertEqual(MacSigninFailure(HibossAPIError.requestFailed(status: 404, message: "")), .notFound)
        XCTAssertEqual(MacSigninFailure(HibossAPIError.requestFailed(status: 500, message: "")), .unreachable)
        XCTAssertEqual(MacSigninFailure(URLError(.notConnectedToInternet)), .unreachable)
    }

    func testPendingRequestPastItsExpiryReadsAsExpired() throws {
        let summary = try FakeSigninAPI.summary(id: requestID, status: "pending")
        let expiry = try XCTUnwrap(ISODate.parse(summary.expiresAt))
        XCTAssertEqual(MacSigninModel.status(of: summary, at: expiry.addingTimeInterval(-1)), .pending)
        XCTAssertEqual(MacSigninModel.status(of: summary, at: expiry), .expired)
        let done = try FakeSigninAPI.summary(id: requestID, status: "completed")
        XCTAssertEqual(MacSigninModel.status(of: done, at: expiry.addingTimeInterval(60)), .completed)
    }

    func testCodeExpiresAtItsDeadline() {
        let expiry = Date(timeIntervalSince1970: 1_000)
        let code = MacSigninCode(code: "306142", deviceLabel: "Mac", expiresAt: expiry)
        XCTAssertFalse(code.isExpired(at: expiry.addingTimeInterval(-1)))
        XCTAssertTrue(code.isExpired(at: expiry))
        XCTAssertFalse(MacSigninCode(code: "306142", deviceLabel: "Mac", expiresAt: nil).isExpired(at: .now))
    }

    func testCodeIsGroupedOnScreenAndSpokenDigitByDigit() {
        XCTAssertEqual(MacSigninCodeView.grouped("306142"), "306 142")
        XCTAssertEqual(MacSigninCodeView.grouped("1234"), "1234")
        XCTAssertEqual(MacSigninCodeView.spokenDigits("306142"), "3 0 6 1 4 2")
    }

    func testPairingScannerStillAcceptsOnlyPairingLinks() {
        var scanned: PairingPayload?
        let scanner = PairingScannerView { scanned = $0 }
        XCTAssertEqual(scanner.recognize(link()), .rejected("That QR code is not a valid HiBoss pairing code."))
        XCTAssertNil(scanned)
        let pair = "hiboss://pair?server=https%3A%2F%2Fhiboss.example&code=hb_pair_" + String(repeating: "e", count: 64)
        XCTAssertEqual(scanner.recognize(pair), .accepted)
        XCTAssertEqual(scanned?.code, "hb_pair_" + String(repeating: "e", count: 64))
    }
}

/// Records each call; a status makes that call fail as the server would.
private final class FakeSigninAPI: SigninApproving, @unchecked Sendable {
    private(set) var calls: [String] = []
    let getStatus: Int?
    let approveStatus: Int?
    let rejectStatus: Int?

    init(getStatus: Int? = nil, approveStatus: Int? = nil, rejectStatus: Int? = nil) {
        self.getStatus = getStatus
        self.approveStatus = approveStatus
        self.rejectStatus = rejectStatus
    }

    static func summary(id: String, status: String) throws -> SigninRequestSummary {
        let json = #"{"request_id":"\#(id)","device_label":"Studio Mac","origin":"NL · Amsterdam","status":"\#(status)","#
            + #""created_at":"2026-10-04T12:00:00.000Z","expires_at":"2026-10-04T12:10:00.000Z"}"#
        return try JSONDecoder().decode(SigninRequestSummary.self, from: Data(json.utf8))
    }

    func signinRequest(id: String) async throws -> SigninRequestSummary {
        calls.append("get \(id)")
        try fail(getStatus)
        return try Self.summary(id: id, status: "pending")
    }

    func approveSignin(id: String) async throws -> SigninApproval {
        calls.append("approve \(id)")
        try fail(approveStatus)
        let json = #"{"code":"306142","expires_at":"2026-10-04T12:10:00.000Z","device_label":"Studio Mac"}"#
        return try JSONDecoder().decode(SigninApproval.self, from: Data(json.utf8))
    }

    func rejectSignin(id: String) async throws {
        calls.append("reject \(id)")
        try fail(rejectStatus)
    }

    private func fail(_ status: Int?) throws {
        if let status { throw HibossAPIError.requestFailed(status: status, message: "") }
    }
}
