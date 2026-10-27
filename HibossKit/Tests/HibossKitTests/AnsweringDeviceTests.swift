// Wire and display regression coverage for additive answering-device attribution.
// Exercises legacy event decoding, reply receipts, metadata, and live resolution.
// Depends on XCTest, HibossKit, and a synthetic URLProtocol transport.

import Foundation
import XCTest
@testable import HibossKit

final class AnsweringDeviceTests: XCTestCase {
    private let json = #"""
    {"id":"q","status":"replied","answer":"Ship","source":"api",
     "answered_by":{"client_id":"phone","kind":"ios","label":"Ming's iPhone"}}
    """#

    func testDeviceLabelOverridesAPIWithoutChangingSource() throws {
        let resolution = try JSONDecoder().decode(OptionResolution.self, from: Data(json.utf8))
        XCTAssertEqual(resolution.source, "api")
        XCTAssertEqual(resolution.sourceLabel, "Ming's iPhone")
        XCTAssertFalse(resolution.isAutoDefault)
        XCTAssertEqual(try JSONDecoder().decode(OptionResolution.self,
            from: JSONEncoder().encode(resolution)), resolution)
    }

    func testDeployedClientShapeStillParsesAdditiveEvent() throws {
        struct LegacyResolution: Decodable {
            let id: MessageID
            let status: ResolutionStatus
            let answer: String?
            let source: String?
        }
        let legacy = try JSONDecoder().decode(LegacyResolution.self, from: Data(json.utf8))
        XCTAssertEqual(legacy.id, "q")
        XCTAssertEqual(legacy.status, .replied)
        XCTAssertEqual(legacy.answer, "Ship")
        XCTAssertEqual(legacy.source, "api")
    }

    func testLegacyRowsAndBlankDeviceNamesKeepKindFallback() throws {
        for (source, label) in [("api", "API"), ("ios", "iOS"), ("macos", "macOS"),
                                ("telegram", "Telegram"), ("discord", "Discord")] {
            let metadata = try JSONDecoder().decode(MessageMetadata.self,
                from: Data("{\"source\":\"\(source)\"}".utf8))
            XCTAssertNil(metadata.answeredBy)
            XCTAssertEqual(metadata.sourceLabel, label)
        }
        let device = AnsweringDevice(clientID: "mac", kind: "macos", label: " \n ")
        XCTAssertEqual(device.displayLabel, "macOS")
        let metadata = MessageMetadata(options: [], source: "api", answeredBy: device)
        XCTAssertEqual(metadata.sourceLabel, "macOS")
        XCTAssertEqual(try JSONDecoder().decode(MessageMetadata.self,
            from: JSONEncoder().encode(metadata)), metadata)
        XCTAssertNil(ReplyOutcome.accepted.answeredBy)
    }

    func testMalformedAnsweredByDoesNotBreakHistoryPageDecoding() throws {
        let pageJSON = #"""
        {"messages":[{"id":"malformed","body":"reply","direction":"boss_to_agent",
        "status":"replied","priority":"normal","created_at":"2026-10-12T10:00:00Z",
        "metadata":{"answered_by":{"client_id":"phone"}}}],"total":1}
        """#

        let page = try JSONDecoder().decode(HistoryResponse.self, from: Data(pageJSON.utf8))
        XCTAssertEqual(page.messages.count, 1)
        XCTAssertNil(page.messages[0].metadata?.answeredBy)
    }

    func testReplyReceiptReturnsServerDeviceImmediately() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeviceReplyProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = HibossAPI(config: ConnectionConfig(
            serverURL: try XCTUnwrap(URL(string: "https://device.test")), bossToken: "synthetic"
        ), session: session)
        let outcome = try await api.reply(to: "q", with: "Ship")
        XCTAssertEqual(outcome.answeredBy?.label, "Ming's iPhone")
    }
}

private final class DeviceReplyProtocol: HTTPTestProtocol, @unchecked Sendable {
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 201,
                                       httpVersion: nil, headerFields: nil)!
        let data = Data(#"""
        {"metadata":{"source":"api",
         "answered_by":{"client_id":"phone","kind":"ios","label":"Ming's iPhone"}}}
        """#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
