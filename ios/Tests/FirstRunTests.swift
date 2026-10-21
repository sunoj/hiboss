// First-run coverage: the HTTPS rule, tapped pairing links and the demo residue purge.
// Exports: FirstRunTests.
// Dependencies: XCTest, HibossKit storage contracts, and the HiBoss app target.

import Foundation
import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class FirstRunTests: XCTestCase {
    func testPlainHTTPServerIsRefusedWithTheHTTPSMessageBeforeAnyRequest() async throws {
        let suite = "FirstRunTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let tokens = MigrationTokenStore(nil)
        let store = ConnectionStore(defaults: defaults, keychain: tokens, sharedDefaults: nil,
                                    signerStore: FirstRunSignerStore(), clientsAPI: { _ in
            XCTFail("An http:// server must be refused before any request")
            return HibossAPI(config: ConnectionConfig(serverURL: URL(fileURLWithPath: "/"), bossToken: "x"))
        })
        store.serverAddress = "http://hiboss.example.com"
        store.bossToken = "hb_token"

        guard case let .failure(error) = await store.connect() else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? ServerAddressError, .requiresHTTPS)
        XCTAssertTrue(error.localizedDescription.contains("HTTPS"))
        XCTAssertEqual(tokens.writes, 0)
    }

    func testHTTPSAndLoopbackAddressesPassTheRule() {
        XCTAssertNil(ServerAddressPolicy.check("https://hiboss.example.com"))
        XCTAssertNil(ServerAddressPolicy.check("hiboss.example.com"))
        XCTAssertNil(ServerAddressPolicy.check("http://localhost:8787"))
        XCTAssertEqual(ServerAddressPolicy.check(" HTTP://10.0.0.2 "), .requiresHTTPS)
        XCTAssertEqual(ServerAddressPolicy.message(for: .insecureServer),
                       ServerAddressError.requiresHTTPS.localizedDescription)
        let ats = URLError(.appTransportSecurityRequiresSecureConnection)
        XCTAssertEqual(ServerAddressPolicy.describe(ats), ServerAddressError.requiresHTTPS.localizedDescription)
    }

    func testTappedPairLinkIsHeldOnceAndOtherLinksAreIgnored() throws {
        let inbox = PairingLinkInbox()
        let code = "hb_pair_" + String(repeating: "a", count: 64)
        inbox.receive(try XCTUnwrap(URL(string: "hiboss://")))
        inbox.receive(try XCTUnwrap(URL(string: "hiboss://signin?server=https%3A%2F%2Fa.example&request=x")))
        XCTAssertNil(inbox.pending)

        inbox.receive(try XCTUnwrap(URL(string: "hiboss://pair?server=https%3A%2F%2Fa.example&code=\(code)")))
        XCTAssertEqual(inbox.pending?.serverURL.absoluteString, "https://a.example")
        XCTAssertEqual(inbox.take()?.code, code)
        XCTAssertNil(inbox.take(), "A link opens the redeem sheet once")
    }

    func testDemoPurgeRemovesReadStateAndDemoDraftsOnly() throws {
        let suite = "FirstRunTests.\(UUID().uuidString)"
        let readsSuite = suite + ".reads"
        let standard = try XCTUnwrap(UserDefaults(suiteName: suite))
        let reads = try XCTUnwrap(UserDefaults(suiteName: readsSuite))
        addTeardownBlock {
            standard.removePersistentDomain(forName: suite)
            reads.removePersistentDomain(forName: readsSuite)
        }
        reads.set(Data("read".utf8), forKey: "session-reads")
        standard.set(Data("draft".utf8), forKey: "hiboss.questionnaire.native-demo-1234.demo-boss.intake.1")
        standard.set(Data("draft".utf8), forKey: "hiboss.questionnaire.home-demo.demo-boss.intake.1")
        standard.set(Data("real".utf8), forKey: "hiboss.questionnaire.https://a.example.boss.intake.1")

        DemoSession.purgeStoredResidue(standard: standard, readsSuite: readsSuite)

        XCTAssertNil(UserDefaults(suiteName: readsSuite)?.data(forKey: "session-reads"))
        XCTAssertNil(standard.data(forKey: "hiboss.questionnaire.native-demo-1234.demo-boss.intake.1"))
        XCTAssertNil(standard.data(forKey: "hiboss.questionnaire.home-demo.demo-boss.intake.1"))
        XCTAssertNotNil(standard.data(forKey: "hiboss.questionnaire.https://a.example.boss.intake.1"),
                        "A real account's draft is not demo residue")
    }

    func testDemoProgressMediaAreBundledFiles() {
        let urls = DemoProgressFixtures.posts.flatMap(\.media).flatMap { [$0.url, $0.posterUrl] }
            .compactMap { $0 }
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            XCTAssertTrue(url.hasPrefix("file://"), "Demo media must not reach the network: \(url)")
        }
    }
}

private struct FirstRunSignerStore: MessageSignerStoring {
    func read() throws -> SecureEnclaveMessageSigner? { nil }
    func write(_ signer: SecureEnclaveMessageSigner) throws {}
    func delete() throws {}
}
