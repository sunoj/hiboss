// Unit coverage for the QR pairing URL parser and its credential shape checks.
// Exports: PairingPayloadTests.
// Dependencies: XCTest and the HiBoss app target.

import XCTest
@testable import HiBoss

final class PairingPayloadTests: XCTestCase {
    func testParsesPercentEncodedServerAndCode() {
        let raw = "hiboss://pair?server=https%3A%2F%2Fhiboss.example%2Fteam%20one&code=hb_pair_\(String(repeating: "a", count: 64))"

        guard case let .success(payload) = PairingPayload.parse(raw) else {
            return XCTFail("Expected pairing URL to parse")
        }
        XCTAssertEqual(payload.serverURL.absoluteString, "https://hiboss.example/team%20one")
        XCTAssertEqual(payload.code, "hb_pair_\(String(repeating: "a", count: 64))")
    }

    func testRejectsMalformedURL() {
        XCTAssertEqual(PairingPayload.parse("hiboss://["), .failure(.malformedURL))
    }

    func testRejectsWrongScheme() {
        let raw = "https://pair?server=https%3A%2F%2Fhiboss.example&code=hb_pair_\(String(repeating: "a", count: 64))"
        XCTAssertEqual(PairingPayload.parse(raw), .failure(.wrongScheme))
    }

    func testRejectsMissingCode() {
        XCTAssertEqual(
            PairingPayload.parse("hiboss://pair?server=https%3A%2F%2Fhiboss.example"),
            .failure(.missingValue)
        )
    }

    func testSanitizesDeviceLabelForServerContract() {
        let raw = "Ming’s iPhone <office>\u{0000} & backup"
        XCTAssertEqual(DeviceLabel.sanitize(raw), "Ming’s iPhone office backup")
        XCTAssertEqual(DeviceLabel.sanitize(String(repeating: "x", count: 101)).count, 100)
    }
}
