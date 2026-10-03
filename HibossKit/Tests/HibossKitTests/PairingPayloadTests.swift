// Unit coverage for the shared pairing link parser, its server rule, and code shape checks.
// Exports: PairingPayloadTests.
// Dependencies: XCTest and HibossKit.

import XCTest
@testable import HibossKit

final class PairingPayloadTests: XCTestCase {
    func testParsesPercentEncodedServerAndCode() {
        let raw = "hiboss://pair?server=https%3A%2F%2Fhiboss.example%2Fteam%20one&code=\(Self.code)"

        guard case let .success(payload) = PairingPayload.parse(raw) else {
            return XCTFail("Expected pairing URL to parse")
        }
        XCTAssertEqual(payload.serverURL.absoluteString, "https://hiboss.example/team%20one")
        XCTAssertEqual(payload.code, Self.code)
        XCTAssertEqual(payload.serverHost, "hiboss.example")
    }

    func testParsesALinkWithSurroundingWhitespace() {
        let raw = "  hiboss://pair?server=https%3A%2F%2Fhiboss.example&code=\(Self.code)\n"
        XCTAssertEqual(try PairingPayload.parse(raw).get().code, Self.code)
    }

    func testRejectsMalformedURL() {
        XCTAssertEqual(PairingPayload.parse("hiboss://["), .failure(.malformedURL))
    }

    func testRejectsWrongScheme() {
        let raw = "https://pair?server=https%3A%2F%2Fhiboss.example&code=\(Self.code)"
        XCTAssertEqual(PairingPayload.parse(raw), .failure(.wrongScheme))
    }

    func testRejectsMissingCode() {
        XCTAssertEqual(
            PairingPayload.parse("hiboss://pair?server=https%3A%2F%2Fhiboss.example"),
            .failure(.missingValue)
        )
        XCTAssertEqual(
            PairingPayload.parse("hiboss://pair?server=https%3A%2F%2Fhiboss.example&code="),
            .failure(.missingValue)
        )
        XCTAssertEqual(PairingPayload.make(server: "hiboss.example", code: "  "), .failure(.missingValue))
    }

    func testRejectsNonHTTPSServer() {
        let raw = "hiboss://pair?server=http%3A%2F%2Fhiboss.example&code=\(Self.code)"
        XCTAssertEqual(PairingPayload.parse(raw), .failure(.insecureServer))
        XCTAssertEqual(
            PairingPayload.make(server: "http://192.168.1.20:8787", code: Self.code),
            .failure(.insecureServer)
        )
        XCTAssertEqual(
            PairingPayload.make(server: "ftp://hiboss.example", code: Self.code),
            .failure(.invalidServerURL)
        )
    }

    func testAllowsPlainHTTPOnlyForLoopbackHosts() throws {
        for server in ["http://localhost:8787", "http://127.0.0.1:8787", "http://LOCALHOST"] {
            let payload = try PairingPayload.make(server: server, code: Self.code).get()
            XCTAssertEqual(payload.serverURL.scheme, "http", server)
        }
        XCTAssertEqual(
            PairingPayload.make(server: "http://localhost.evil.example", code: Self.code),
            .failure(.insecureServer)
        )
    }

    func testTypedBareHostDefaultsToHTTPS() throws {
        let payload = try PairingPayload.make(server: " hiboss.example ", code: " \(Self.code) ").get()
        XCTAssertEqual(payload.serverURL.absoluteString, "https://hiboss.example")
        XCTAssertEqual(payload.code, Self.code)
    }

    func testRejectsAMalformedCode() {
        XCTAssertEqual(
            PairingPayload.make(server: "https://hiboss.example", code: "hb_pair_short"),
            .failure(.invalidCode)
        )
        XCTAssertEqual(
            PairingPayload.make(server: "https://hiboss.example", code: "hb_live_token"),
            .failure(.invalidCode)
        )
    }

    func testEveryErrorHasACatalogMessage() {
        let errors: [PairingPayloadError] = [
            .malformedURL, .wrongScheme, .missingValue, .invalidServerURL, .insecureServer, .invalidCode,
        ]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error)")
        }
        XCTAssertEqual(
            PairingPayloadError.insecureServer.errorDescription,
            kitL("The server must use HTTPS. Plain HTTP is allowed only for localhost.")
        )
    }

    private static let code = "hb_pair_" + String(repeating: "a", count: 64)
}
