// Verifies the server's Box metadata shape, opaque pages and patch field semantics.
// Exports BoxModelTests; the fixture carries every public field and no storage key.
// Dependencies: XCTest, Foundation, HibossKit and HiBoss presentation helpers.

import HibossKit
import XCTest
@testable import HiBoss

final class BoxModelTests: XCTestCase {
    static let itemJSON = """
    {"id":"bx_reference","boss_id":"boss","boss_name":"Owner","kind":"image",
     "text":"Reference","url":null,"note":"Use this","project":"hiboss","tags":["layout"],
     "source":"ios-share","has_media":true,"media_type":"image/png","media_bytes":10,
     "width":2,"height":5,"duration_ms":null,"created_at":"2026-10-07T12:00:00.000Z"}
    """

    func testDecodesEveryPublicMediaFieldAndRoundTripsWithoutStorageKeys() throws {
        let item = try JSONDecoder().decode(BoxItem.self, from: Data(Self.itemJSON.utf8))
        XCTAssertEqual(item.id, "bx_reference")
        XCTAssertEqual(item.bossID, "boss")
        XCTAssertEqual(item.bossName, "Owner")
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.source, .iosShare)
        XCTAssertEqual(item.tags, ["layout"])
        XCTAssertEqual(item.mediaType, "image/png")
        XCTAssertEqual(item.mediaBytes, 10)
        XCTAssertEqual(item.width, 2)
        XCTAssertEqual(item.height, 5)
        XCTAssertTrue(item.hasMedia)
        XCTAssertNil(item.durationMs)
        let encoded = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(BoxItem.self, from: encoded), item)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(keys["media_key"])
        XCTAssertNil(keys["deleted_at"])
    }

    func testDecodesAllKindsSourcesAndNullableMetadata() throws {
        for kind in BoxItem.Kind.allCases {
            for source in ["ios-share", "mac-share", "mac-drop", "cli"] {
                let json = """
                {"id":"bx_nullable","boss_id":"b","boss_name":"B","kind":"\(kind.rawValue)",
                 "source":"\(source)","tags":[],"has_media":false,"text":null,"url":null,"note":null,
                 "project":null,"media_type":null,"media_bytes":null,"width":null,"height":null,
                 "duration_ms":null,"created_at":"2026-10-07T00:00:00Z"}
                """
                let item = try JSONDecoder().decode(BoxItem.self, from: Data(json.utf8))
                XCTAssertEqual(item.kind, kind)
                XCTAssertEqual(item.source.rawValue, source)
                XCTAssertNil(item.text)
                XCTAssertNil(item.project)
                XCTAssertFalse(item.hasMedia)
            }
        }
    }

    func testCursorRemainsAnOpaqueStringAndRejectsProgressCursorObjects() throws {
        let cursor = "opaque_server-cursor"
        let data = Data("{\"items\":[\(Self.itemJSON)],\"next_cursor\":\"\(cursor)\"}".utf8)
        let page = try JSONDecoder().decode(BoxPage.self, from: data)
        XCTAssertEqual(page.nextCursor, cursor)
        XCTAssertEqual(page.items.count, 1)
        let last = try JSONDecoder().decode(
            BoxPage.self, from: Data(#"{"items":[],"next_cursor":null}"#.utf8))
        XCTAssertNil(last.nextCursor)
        XCTAssertThrowsError(try JSONDecoder().decode(BoxPage.self, from: Data(
            #"{"items":[],"next_cursor":{"created_at":"date","id":"id"}}"#.utf8)))
    }

    func testProvenanceUsesNamedOrGenericAgentLabelsAndHidesBossLabels() {
        func item(_ author: BoxAuthor?) -> BoxItem {
            BoxItem(id: "reference", bossID: "boss", bossName: "Owner", kind: .text,
                createdAt: "2026-10-09T00:00:00Z", addedBy: author)
        }
        XCTAssertNil(item(nil).provenanceLabel)
        XCTAssertNil(item(.boss).provenanceLabel)
        let named = item(.agent(id: "agent", name: " Researcher \n")).provenanceLabel
        XCTAssertEqual(named, String(localized: "Added by \("Researcher")"))
        for name in [nil, "", " \n\t"] as [String?] {
            XCTAssertEqual(item(.agent(id: "agent", name: name)).provenanceLabel,
                String(localized: "Added by an agent"))
        }
    }

    func testPatchDistinguishesOmittedClearedAndReplacedFields() throws {
        let data = try JSONEncoder().encode(BoxPatch(note: .value(nil), tags: []))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(json["note"] is NSNull)
        XCTAssertNil(json["project"])
        XCTAssertEqual(json["tags"] as? [String], [])
        let replacement = try JSONEncoder().encode(BoxPatch(
            note: .value("caption"), project: .value("project")))
        let replaced = try XCTUnwrap(JSONSerialization.jsonObject(with: replacement) as? [String: Any])
        XCTAssertEqual(replaced["note"] as? String, "caption")
        XCTAssertEqual(replaced["project"] as? String, "project")
        XCTAssertNil(replaced["tags"])
    }
}
