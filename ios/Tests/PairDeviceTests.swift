// Covers the iOS Pair another device flow: role-denied copy and the shared link contract.
// Exports: PairDeviceTests.
// Dependencies: XCTest, HibossKit pairing types, and the HiBoss app target.

import Foundation
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class PairDeviceTests: XCTestCase {
    func testForbiddenIssueShowsTheRoleMessage() async {
        let model = DevicePairingModel(
            serverURL: URL(string: "https://hiboss.example"),
            issuer: ForbiddenIssuer()
        )

        await model.requestCode()

        XCTAssertEqual(model.state(at: .now), .permissionDenied)
        XCTAssertEqual(model.requestFailure?.title, "Your role cannot pair devices")
        XCTAssertNil(model.failureMessage, "A role denial is not shown as a generic error")
    }

    func testScannedLinkUsesTheSharedParserAndItsHTTPSRule() {
        let code = "hb_pair_" + String(repeating: "e", count: 64)
        XCTAssertEqual(
            PairingPayload.parse("hiboss://pair?server=http%3A%2F%2Fhiboss.example&code=\(code)"),
            .failure(.insecureServer)
        )
        XCTAssertEqual(
            try PairingPayload.parse("hiboss://pair?server=https%3A%2F%2Fhiboss.example&code=\(code)").get().code,
            code
        )
    }

    func testDeviceLabelFallsBackToIPhone() {
        XCTAssertEqual(DeviceLabel.sanitize("  ", fallback: "iPhone"), "iPhone")
    }
}

private struct ForbiddenIssuer: PairingIssuing {
    func requestPairingCode() async throws -> PairingGrant {
        throw HibossAPIError.requestFailed(status: 403, message: "admin required")
    }

    func pairingStatus(code: String) async throws -> PairingStatus { .pending }
}
