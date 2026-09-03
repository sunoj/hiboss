// Pure pairing-flow tests for deep-link encoding, expiry presentation, and QR generation.
// Exports: PairingLogicTests.
// Dependencies: XCTest, Foundation, AppKit, and the macOS pairing helpers.

import AppKit
import Foundation
import XCTest
@testable import HibossIsland

final class PairingLogicTests: XCTestCase {
    func testPairingLinkPercentEncodesTheCompleteServerURL() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://hiboss.example/boss?region=base"))
        let link = try PairingLink(serverURL: serverURL, code: Self.validCode)

        XCTAssertEqual(
            link.url.absoluteString,
            "hiboss://pair?server=https%3A%2F%2Fhiboss.example%2Fboss%3Fregion%3Dbase&code=\(Self.validCode)"
        )
        XCTAssertEqual(URLComponents(url: link.url, resolvingAgainstBaseURL: false)?.host, "pair")
    }

    func testPairingValidityStopsOfferingTheCodeAtExpiration() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expiresAt = Date(timeIntervalSince1970: 1_125.2)

        XCTAssertTrue(PairingValidity.isValid(expiresAt: expiresAt, now: now))
        XCTAssertEqual(PairingValidity.remainingSeconds(expiresAt: expiresAt, now: now), 126)
        XCTAssertFalse(PairingValidity.isValid(expiresAt: now, now: now))
        XCTAssertEqual(PairingValidity.remainingSeconds(expiresAt: now, now: now), 0)
        XCTAssertEqual(PairingValidity.formatted(remainingSeconds: 125), "2:05")
    }

    func testQRCodeGeneratorProducesAnImageForThePairingLink() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://hiboss.example"))
        let link = try PairingLink(serverURL: serverURL, code: Self.validCode)

        let image = try XCTUnwrap(PairingQRCodeGenerator.image(for: link))

        XCTAssertFalse(image.representations.isEmpty)
    }

    private static let validCode = "hb_pair_" + String(repeating: "a", count: 64)
}
