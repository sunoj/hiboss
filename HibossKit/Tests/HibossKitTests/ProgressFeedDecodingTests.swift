// Decoder coverage for the progress-feed wire format.
// Exports: ProgressFeedDecodingTests for posts with and without media dimensions.
// Dependencies: XCTest and HibossKit Codable models.

import XCTest
@testable import HibossKit

final class ProgressFeedDecodingTests: XCTestCase {
    func testDecodesPostWithNoMedia() throws {
        let json = """
        {
          "id": "p1",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "session_id": null,
          "body": "Shipped the progress feed. Migration + 4 endpoints.",
          "media": [],
          "tags": [],
          "created_at": "2026-08-14T09:00:00Z"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.id, "p1")
        XCTAssertEqual(post.project, "hiboss")
        XCTAssertEqual(post.agentId, "ak1")
        XCTAssertEqual(post.agentName, "hiboss-cli")
        XCTAssertNil(post.sessionId)
        XCTAssertEqual(post.body, "Shipped the progress feed. Migration + 4 endpoints.")
        XCTAssertEqual(post.media, [])
        XCTAssertEqual(post.tags, [])
        XCTAssertEqual(post.createdAt, "2026-08-14T09:00:00Z")
    }

    func testDecodesPostWithImage() throws {
        let json = """
        {
          "id": "p2",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "New tab screenshot.",
          "media": [{
            "url": "https://hiboss.example/api/attachments/shot.png",
            "kind": "image",
            "content_type": "image/png",
            "size": 20480,
            "width": 1200,
            "height": 800,
            "alt": "screenshot of the new tab"
          }],
          "tags": ["release"],
          "created_at": "2026-08-14T09:01:00Z"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.media.count, 1)
        let media = try XCTUnwrap(post.media.first)
        XCTAssertEqual(media.kind, .image)
        XCTAssertEqual(media.contentType, "image/png")
        XCTAssertEqual(media.size, 20480)
        XCTAssertEqual(media.width, 1200)
        XCTAssertEqual(media.height, 800)
        XCTAssertNil(media.durationMs)
        XCTAssertNil(media.posterUrl)
        XCTAssertEqual(media.alt, "screenshot of the new tab")
        XCTAssertEqual(post.tags, ["release"])
    }

    func testDecodesPostWithVideoPosterAndDuration() throws {
        let json = """
        {
          "id": "p3",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "session_id": "abc123",
          "body": "Short clip of the looping player.",
          "media": [{
            "url": "https://hiboss.example/api/attachments/clip.mp4",
            "kind": "video",
            "content_type": "video/mp4",
            "size": 512000,
            "width": 1080,
            "height": 1920,
            "duration_ms": 3200,
            "poster_url": "https://hiboss.example/api/attachments/clip.jpg",
            "alt": "looping demo clip"
          }],
          "tags": ["demo"],
          "created_at": "2026-08-14T09:02:00Z"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        let media = try XCTUnwrap(post.media.first)
        XCTAssertEqual(media.kind, .video)
        XCTAssertEqual(media.durationMs, 3200)
        XCTAssertEqual(media.posterUrl, "https://hiboss.example/api/attachments/clip.jpg")
        XCTAssertEqual(media.width, 1080)
        XCTAssertEqual(media.height, 1920)
        XCTAssertEqual(post.sessionId, "abc123")
    }

    func testDecodesMediaWhenWidthAndHeightAreAbsent() throws {
        let json = """
        {
          "id": "p4",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "Image without probed dimensions.",
          "media": [{
            "url": "https://hiboss.example/api/attachments/plain.png",
            "kind": "image",
            "content_type": "image/png",
            "size": 1024
          }],
          "created_at": "2026-08-14T09:03:00Z"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        let media = try XCTUnwrap(post.media.first)
        XCTAssertNil(media.width)
        XCTAssertNil(media.height)
        XCTAssertEqual(post.tags, [])
        XCTAssertEqual(post.media.count, 1)
    }

    func testNullMediaAndTagsBecomeEmptyArrays() throws {
        let json = """
        {
          "id": "p5",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "Null collections.",
          "media": null,
          "tags": null,
          "created_at": "2026-08-14T09:04:00Z"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.media, [])
        XCTAssertEqual(post.tags, [])
    }
}
