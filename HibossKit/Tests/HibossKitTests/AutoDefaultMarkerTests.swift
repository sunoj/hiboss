// The automatic-answer marker: `auto_default: true` on reply metadata, whatever the source.
// Exports: AutoDefaultMarkerTests. Dependencies: XCTest, HibossKit decoding.

import Foundation
import HibossKit
import XCTest

final class AutoDefaultMarkerTests: XCTestCase {
    private func metadata(_ json: String) throws -> MessageMetadata {
        try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
    }

    func testHistoricalTimeoutReplyWithApiSourceIsAutomatic() throws {
        let decoded = try metadata(#"{"auto_default":true,"source":"api"}"#)
        XCTAssertTrue(decoded.isAutoDefault)
        XCTAssertEqual(decoded.source, "api")
    }

    func testCurrentTimeoutReplyWithSystemSourceIsAutomatic() throws {
        let decoded = try metadata(#"{"auto_default":true,"source":"system","provenance":{"version":1}}"#)
        XCTAssertTrue(decoded.isAutoDefault)
        XCTAssertEqual(decoded.source, "system")
    }

    func testBossReplyIsNeverAutomaticWithoutTheMarker() throws {
        XCTAssertFalse(try metadata(#"{"source":"api"}"#).isAutoDefault)
        XCTAssertFalse(try metadata(#"{"source":"system"}"#).isAutoDefault, "source alone is not the marker")
        XCTAssertFalse(try metadata(#"{"auto_default":false,"source":"ios"}"#).isAutoDefault)
        XCTAssertFalse(try metadata(#"{"auto_default":"yes"}"#).isAutoDefault)
    }

    func testMarkerSurvivesAnEncodeRoundTrip() throws {
        let original = MessageMetadata(options: [], source: "api", isAutoDefault: true)
        let decoded = try JSONDecoder().decode(MessageMetadata.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(decoded.isAutoDefault)
    }

    func testTranscriptReplyReadsTheSameMarker() throws {
        func event(_ metadata: String) throws -> SessionEvent {
            let json = #"{"id":"e1","session_id":"s","sequence":1,"kind":"message","direction":"boss_to_agent","#
                + #""payload":{"body":"Keep","metadata":\#(metadata)},"created_at":"2026-10-04T00:00:00Z"}"#
            return try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        }
        XCTAssertTrue(try event(#"{"auto_default":true,"source":"api"}"#).isAutoDefaultReply)
        XCTAssertTrue(try event(#"{"auto_default":true,"source":"system"}"#).isAutoDefaultReply)
        XCTAssertFalse(try event(#"{"source":"ios"}"#).isAutoDefaultReply)
    }

    func testStreamResolutionCarriesTheServerEncodingOfTheMarker() {
        XCTAssertTrue(OptionResolution(id: "q", status: .replied, answer: "Keep", source: "system").isAutoDefault)
        XCTAssertFalse(OptionResolution(id: "q", status: .replied, answer: "Keep", source: "api").isAutoDefault)
        XCTAssertFalse(OptionResolution(id: "q", status: .expired, source: "system").isAutoDefault)
    }
}
