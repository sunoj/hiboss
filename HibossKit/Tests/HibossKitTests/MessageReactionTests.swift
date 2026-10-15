// Reaction wire-shape, tolerance and aggregation coverage.
// Exports: MessageReactionTests for shared metadata.
// Dependencies: XCTest, Foundation and HibossKit.

import Foundation
import HibossKit
import XCTest

final class MessageReactionTests: XCTestCase {
    func testAllShapesDeduplicateAndGroupInFirstSeenOrder() throws {
        let metadata = try decode("""
        [
          {"emoji":"👍","actor":"agent","actor_id":"a","created_at":"2026-10-08T10:00:00Z"},
          {"emoji":"❤️","boss_id":"b"},
          {"emoji":"👍","user":"b"},
          {"emoji":"👍","boss_id":"b"},
          {"emoji":"👍","actor":"boss","actor_id":"a","created_at":"2026-10-08T10:01:00Z"}
        ]
        """)
        XCTAssertEqual(metadata.reactions.count, 4)
        XCTAssertEqual(metadata.reactions.map(\.actor), [.agent, .boss, .boss, .boss])
        guard metadata.reactions.count == 4 else { return }
        XCTAssertNil(metadata.reactions[1].createdAt)
        XCTAssertEqual(metadata.reactionGroups.map(\.emoji), ["👍", "❤️"])
        XCTAssertEqual(metadata.reactionGroups.map(\.count), [3, 1])
        guard metadata.reactionGroups.count == 2 else { return }
        XCTAssertTrue(metadata.reactionGroups[0].bossReacted)
        XCTAssertTrue(metadata.reactionGroups[0].agentReacted)
        XCTAssertFalse(metadata.reactionGroups[1].agentReacted)
    }

    func testMalformedEntriesDoNotDiscardValidNeighbors() throws {
        let metadata = try decode("""
        [null, 4, [], {}, {"emoji":"👍","actor":"unknown","actor_id":"a"},
         {"emoji":"","user":"b"}, {"emoji":"👍","boss_id":3},
         {"emoji":"👍","actor":"agent","actor_id":"a","created_at":"bad"},
         {"emoji":"👍","actor":"agent","actor_id":"a"},
         {"emoji":"👍","user":"valid"}]
        """)
        XCTAssertEqual(metadata.reactions.count, 1)
        XCTAssertEqual(metadata.reactions.first?.actorID, "valid")
        for value in ["null", "{}", "\"bad\""] {
            XCTAssertTrue(try decode(value).reactions.isEmpty)
        }
        XCTAssertTrue(try JSONDecoder().decode(MessageMetadata.self, from: Data("{}".utf8)).reactions.isEmpty)
    }

    func testEncodingPreservesNormalizedAndLegacyReactions() throws {
        let metadata = try decode("""
        [{"emoji":"👍","user":"b"},
         {"emoji":"❤️","actor":"agent","actor_id":"a","created_at":"2026-10-08T10:00:00Z"}]
        """)
        let data = try JSONEncoder().encode(metadata)
        XCTAssertEqual(try JSONDecoder().decode(MessageMetadata.self, from: data), metadata)
    }

    private func decode(_ reactions: String) throws -> MessageMetadata {
        try JSONDecoder().decode(MessageMetadata.self,
                                 from: Data("{\"reactions\":\(reactions)}".utf8))
    }
}
