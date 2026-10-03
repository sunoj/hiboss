// Flow coverage for issuing a pairing code and observing its redemption.
// Exports: DevicePairingModelTests for ready, redeemed, role-denied, and unconfigured states.
// Dependencies: XCTest and HibossKit's DevicePairingModel with a stub issuer.

import Foundation
import XCTest
@testable import HibossKit

@MainActor
final class DevicePairingModelTests: XCTestCase {
    func testIssuedCodeBecomesAReadyLinkWithAQRImage() async throws {
        let issuer = StubIssuer(grant: .success(try Self.grant()), statuses: [])
        let model = DevicePairingModel(serverURL: Self.server, issuer: issuer)

        await model.requestCode()

        guard case let .ready(grant, link) = model.state(at: .now) else {
            return XCTFail("Expected a ready state, got \(model.state(at: .now))")
        }
        XCTAssertEqual(grant.code, Self.code)
        XCTAssertEqual(try PairingPayload.parse(link.url.absoluteString).get().code, Self.code)
        XCTAssertFalse(link.url.absoluteString.contains("token"))
        XCTAssertNotNil(model.qrImage)
    }

    func testMonitorReportsTheRedeemedDevice() async throws {
        let issuer = StubIssuer(
            grant: .success(try Self.grant()), statuses: [.pending, .paired(deviceLabel: "Studio Mac")]
        )
        let model = DevicePairingModel(serverURL: Self.server, issuer: issuer, pollInterval: .milliseconds(1))

        await model.requestCode()
        await model.monitorRedemption()

        XCTAssertEqual(model.state(at: .now), .paired(deviceLabel: "Studio Mac"))
    }

    func testForbiddenIssueMapsToTheRoleMessage() async {
        let issuer = StubIssuer(
            grant: .failure(HibossAPIError.requestFailed(status: 403, message: "admin required")), statuses: []
        )
        let model = DevicePairingModel(serverURL: Self.server, issuer: issuer)

        await model.requestCode()

        XCTAssertEqual(model.state(at: .now), .permissionDenied)
        XCTAssertEqual(model.requestFailure, .permissionDenied)
        XCTAssertNil(model.failureMessage)
        XCTAssertEqual(model.requestFailure?.title, kitL("Your role cannot pair devices"))
        XCTAssertEqual(
            PairingRequestFailure.permissionDenied.title,
            englishCatalogValue("Your role cannot pair devices")
        )
    }

    func testOtherIssueFailuresStayRetryable() async {
        let issuer = StubIssuer(
            grant: .failure(HibossAPIError.requestFailed(status: 500, message: "")), statuses: []
        )
        let model = DevicePairingModel(serverURL: Self.server, issuer: issuer)

        await model.requestCode()

        XCTAssertEqual(model.state(at: .now), .requestFailed)
        XCTAssertNotNil(model.failureMessage)
    }

    func testMissingConnectionIsReportedBeforeAnyRequest() async {
        let model = DevicePairingModel(config: nil)
        await model.requestCode()
        XCTAssertEqual(model.state(at: .now), .notConfigured)
    }

    private func englishCatalogValue(_ key: String) -> String? {
        guard let url = kitResourceBundle.url(forResource: "en", withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return nil }
        return bundle.localizedString(forKey: key, value: "<missing>", table: nil)
    }

    private static let code = "hb_pair_" + String(repeating: "c", count: 64)
    private static let server = URL(string: "https://hiboss.example")

    private static func grant() throws -> PairingGrant {
        try PairingGrant(code: code, expiresAt: Date().addingTimeInterval(300))
    }
}

private final class StubIssuer: PairingIssuing, @unchecked Sendable {
    private let grant: Result<PairingGrant, Error>
    private var statuses: [PairingStatus]
    private let lock = NSLock()

    init(grant: Result<PairingGrant, Error>, statuses: [PairingStatus]) {
        self.grant = grant
        self.statuses = statuses
    }

    func requestPairingCode() async throws -> PairingGrant {
        try grant.get()
    }

    func pairingStatus(code: String) async throws -> PairingStatus {
        lock.withLock { statuses.isEmpty ? .expired : statuses.removeFirst() }
    }
}
