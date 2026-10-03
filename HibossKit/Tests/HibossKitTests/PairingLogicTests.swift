// Pure pairing-flow tests for deep-link encoding, expiry presentation, and QR generation.
// Exports: PairingLogicTests.
// Dependencies: XCTest, Foundation, and the HibossKit pairing helpers.

import Foundation
import XCTest
@testable import HibossKit

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
        XCTAssertEqual(PairingValidity.formatted(remainingSeconds: 125, locale: Locale(identifier: "en_US")), "2:05")
    }

    func testQRCodeGeneratorProducesAnImageForThePairingLink() throws {
        let serverURL = try XCTUnwrap(URL(string: "https://hiboss.example"))
        let link = try PairingLink(serverURL: serverURL, code: Self.validCode)

        let image = try XCTUnwrap(PairingQRCode.cgImage(for: link))

        XCTAssertGreaterThan(image.width, 100)
    }

    func testPairingLinkRoundTripsThroughTheSharedParser() throws {
        let link = try Self.link()
        XCTAssertEqual(
            PairingPayload.parse(link.url.absoluteString),
            .success(PairingPayload(serverURL: try XCTUnwrap(URL(string: "https://hiboss.example")), code: Self.validCode))
        )
    }

    func testPairingLinkRefusesAServerTheReceiverWouldReject() throws {
        let lanServer = try XCTUnwrap(URL(string: "http://192.168.1.20:8787"))
        XCTAssertThrowsError(try PairingLink(serverURL: lanServer, code: Self.validCode)) { error in
            XCTAssertEqual(error as? PairingLinkError, .invalidServerURL)
        }
    }

    func testPairingContentStateShowsProgressWhileRequesting() {
        XCTAssertEqual(
            PairingContentState.derive(
                grant: nil,
                hasConfiguredServer: false,
                now: Date(),
                isRequesting: true,
                requestFailure: nil,
                linkResult: nil,
                canRenderQRCode: false
            ),
            .requesting
        )
    }

    func testPairingContentStateReportsMissingConfiguration() {
        XCTAssertEqual(Self.deriveState(hasConfiguredServer: false), .notConfigured)
    }

    func testPairingContentStateReportsMissingCode() {
        XCTAssertEqual(Self.deriveState(), .noCode)
    }

    func testPairingContentStateReportsExpiredCode() throws {
        let grant = try Self.grant(expiresIn: -1)
        XCTAssertEqual(Self.deriveState(grant: grant), .expired)
    }

    func testPairingContentStateReportsPermissionDenied() {
        XCTAssertEqual(
            Self.deriveState(requestFailure: .permissionDenied),
            .permissionDenied
        )
        XCTAssertEqual(
            PairingRequestFailure.from(HibossAPIError.requestFailed(status: 403, message: "admin required")),
            .permissionDenied
        )
    }

    func testPairingContentStateReportsRequestFailure() {
        XCTAssertEqual(Self.deriveState(requestFailure: .failed), .requestFailed)
        XCTAssertEqual(
            PairingRequestFailure.from(HibossAPIError.requestFailed(status: 500, message: "unavailable")),
            .failed
        )
    }

    func testPairingContentStateReportsInvalidLink() throws {
        let grant = try Self.grant(expiresIn: 300)
        XCTAssertEqual(
            Self.deriveState(grant: grant, linkResult: .failure(.invalidServerURL)),
            .invalidLink
        )
    }

    func testPairingContentStateReportsUnavailableQRCode() throws {
        let grant = try Self.grant(expiresIn: 300)
        let link = try Self.link()
        XCTAssertEqual(
            Self.deriveState(grant: grant, linkResult: .success(link), canRenderQRCode: false),
            .qrUnavailable
        )
    }

    func testPairingContentStateCarriesReadyGrantAndLink() throws {
        let grant = try Self.grant(expiresIn: 300)
        let link = try Self.link()
        let state = Self.deriveState(grant: grant, linkResult: .success(link), canRenderQRCode: true)

        guard case let .ready(actualGrant, actualLink) = state else {
            return XCTFail("Expected a ready pairing state")
        }
        XCTAssertEqual(actualGrant, grant)
        XCTAssertEqual(actualLink, link)
    }

    func testPairingContentStateKeepsObservedSuccessAfterCodeExpires() throws {
        let grant = try Self.grant(expiresIn: -1)

        XCTAssertEqual(
            Self.deriveState(grant: grant, pairedDeviceLabel: "Ming’s iPhone"),
            .paired(deviceLabel: "Ming’s iPhone")
        )
    }

    private static func deriveState(
        grant: PairingGrant? = nil,
        hasConfiguredServer: Bool = true,
        requestFailure: PairingRequestFailure? = nil,
        linkResult: Result<PairingLink, PairingLinkError>? = nil,
        canRenderQRCode: Bool = false,
        pairedDeviceLabel: String? = nil
    ) -> PairingContentState {
        PairingContentState.derive(
            grant: grant,
            hasConfiguredServer: hasConfiguredServer,
            now: Date(timeIntervalSince1970: 1_000),
            isRequesting: false,
            requestFailure: requestFailure,
            linkResult: linkResult,
            canRenderQRCode: canRenderQRCode,
            pairedDeviceLabel: pairedDeviceLabel
        )
    }

    private static func grant(expiresIn: TimeInterval) throws -> PairingGrant {
        try PairingGrant(
            code: validCode,
            expiresAt: Date(timeIntervalSince1970: 1_000 + expiresIn)
        )
    }

    private static func link() throws -> PairingLink {
        let serverURL = try XCTUnwrap(URL(string: "https://hiboss.example"))
        return try PairingLink(serverURL: serverURL, code: validCode)
    }

    private static let validCode = "hb_pair_" + String(repeating: "a", count: 64)
}
