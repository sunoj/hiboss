// Covers redeeming a pairing code on the Mac: link routing, form validation, and token storage.
// Exports: PairWithCodeTests.
// Dependencies: XCTest, HibossKit pairing types, and the HibossIsland settings and router.

import Foundation
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class PairWithCodeTests: XCTestCase {
    func testClickedPairLinkOpensSettingsWithThePrefilledSheetButNeverRedeems() {
        var opened = 0
        let router = PairingLinkRouter(activate: {})
        router.install { opened += 1 }

        XCTAssertTrue(router.receive(Self.link))

        XCTAssertEqual(opened, 1)
        XCTAssertEqual(router.request?.link, Self.link.absoluteString)
        XCTAssertFalse(router.receive(URL(string: "hiboss://other?x=1")!))
        XCTAssertFalse(router.receive(URL(string: "https://pair.example")!))
    }

    func testLinkReceivedBeforeTheOpenerIsInstalledIsReplayed() async {
        var opened = 0
        let router = PairingLinkRouter(activate: {})
        router.receive(Self.link)
        router.install { opened += 1 }
        await Task.yield()
        XCTAssertEqual(opened, 1)
        XCTAssertNotNil(router.request)
    }

    func testPastedLinkFillsServerAndCode() {
        let form = PairWithCodeForm(link: Self.link.absoluteString)
        XCTAssertEqual(form.server, "https://hiboss.example")
        XCTAssertEqual(form.code, Self.code)
        XCTAssertEqual(form.payload?.serverHost, "hiboss.example")
        XCTAssertNil(form.issue)
    }

    func testInsecureLinkIsRejectedAndOffersNoConfirm() {
        let form = PairWithCodeForm(link: "hiboss://pair?server=http%3A%2F%2Fhiboss.example&code=\(Self.code)")
        XCTAssertEqual(form.issue, .insecureServer)
        XCTAssertNil(form.payload)
    }

    func testTypedServerAndCodeValidateWithoutALink() {
        var form = PairWithCodeForm()
        XCTAssertNil(form.issue, "An untouched form shows no error")
        form.server = "hiboss.example"
        XCTAssertEqual(form.issue, .missingValue)
        form.code = Self.code
        XCTAssertEqual(form.payload?.serverURL.absoluteString, "https://hiboss.example")
    }

    func testRedeemStoresTheReturnedTokenInTheKeychainLikeManualLogin() async throws {
        let suite = "PairWithCodeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let tokens = PairingTokens()
        let redeemer = StubRedeemer()
        let settings = AppSettings(defaults: defaults, keychain: tokens, redeemer: redeemer)
        settings.deviceLabel = "Studio <Mac>"
        let payload = try PairingWithCode.payload()

        let config = try await settings.pair(with: payload).get()

        XCTAssertEqual(config.serverURL.absoluteString, "https://hiboss.example")
        XCTAssertEqual(try tokens.read(), "hb_boss_paired")
        XCTAssertEqual(settings.activeClientConfig, config)
        XCTAssertEqual(defaults.string(forKey: AppConstants.Storage.serverURL), "https://hiboss.example")
        let calls = await redeemer.calls
        XCTAssertEqual(calls, ["\(Self.code)|Studio Mac|unsigned"])
    }

    func testFailedRedeemStoresNothing() async throws {
        let suite = "PairWithCodeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let tokens = PairingTokens()
        let settings = AppSettings(defaults: defaults, keychain: tokens, redeemer: StubRedeemer(fails: true))

        guard case let .failure(error) = await settings.pair(with: try PairingWithCode.payload()) else {
            return XCTFail("Expected an expired code to fail")
        }
        XCTAssertEqual(error as? PairingRedeemError, .invalidOrExpired)
        XCTAssertNil(try tokens.read())
        XCTAssertNil(settings.activeClientConfig)
    }

    private static let code = pairingTestCode
    private static let link = URL(string: "hiboss://pair?server=https%3A%2F%2Fhiboss.example&code=\(code)")!
}

private let pairingTestCode = "hb_pair_" + String(repeating: "d", count: 64)

private enum PairingWithCode {
    static func payload() throws -> PairingPayload {
        try PairingPayload.make(server: "https://hiboss.example", code: pairingTestCode).get()
    }
}

private actor StubRedeemer: PairingRedeeming {
    let fails: Bool
    var calls: [String] = []

    init(fails: Bool = false) { self.fails = fails }

    func redeem(
        payload: PairingPayload, deviceLabel: String, signing: PairingSigningRegistration?
    ) async throws -> PairingRedemptionGrant {
        calls.append("\(payload.code)|\(deviceLabel)|\(signing == nil ? "unsigned" : "signed")")
        if fails { throw PairingRedeemError.invalidOrExpired }
        return PairingRedemptionGrant(token: "hb_boss_paired", bossID: "boss-1", signingKeyID: nil)
    }
}

private final class PairingTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    func read() throws -> String? { lock.withLock { token } }
    func write(_ token: String) throws { lock.withLock { self.token = token } }
}
