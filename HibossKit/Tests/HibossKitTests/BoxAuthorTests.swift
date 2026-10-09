// Covers decoding Box item provenance from `added_by`, including older servers.
// An unknown or malformed author must never fail the page or read as the boss.

import XCTest
@testable import HibossKit

final class BoxAuthorTests: XCTestCase {
    private func item(_ addedBy: String?) throws -> BoxItem {
        let extra = addedBy.map { #","added_by":\#($0)"# } ?? ""
        let json = #"{"id":"bx_1","boss_id":"b","boss_name":"Boss","kind":"text","text":"t","#
            + #""tags":[],"source":"cli","has_media":false,"created_at":"2026-10-09T00:00:00Z"\#(extra)}"#
        return try JSONDecoder().decode(BoxItem.self, from: Data(json.utf8))
    }

    func testMissingAddedByMeansBoss() throws {
        XCTAssertEqual(try item(nil).author, .boss)
    }

    func testBossAuthor() throws {
        XCTAssertEqual(try item(#"{"kind":"boss"}"#).author, .boss)
    }

    func testAgentAuthor() throws {
        let author = try item(#"{"kind":"agent","id":"k1","name":"house-agent"}"#).author
        XCTAssertEqual(author, .agent(id: "k1", name: "house-agent"))
        XCTAssertFalse(author.isBoss)
    }

    func testUnknownKindIsNeverTheBoss() throws {
        XCTAssertFalse(try item(#"{"kind":"robot"}"#).author.isBoss)
    }

    func testMalformedAuthorDoesNotFailTheItem() throws {
        XCTAssertFalse(try item(#"{"kind":7,"name":["x"]}"#).author.isBoss)
        XCTAssertFalse(try item(#""agent""#).author.isBoss)
    }

    func testRoundTrip() throws {
        let original = try item(#"{"kind":"agent","id":"k1","name":"a"}"#)
        let again = try JSONDecoder().decode(BoxItem.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(again, original)
    }
}
