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
        XCTAssertEqual(post.team, ProgressTeam.fallback(project: "hiboss"))
        XCTAssertEqual(post.likeCount, 0)
        XCTAssertFalse(post.liked)
        XCTAssertNil(post.agentLabel)
        XCTAssertNil(post.model)
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

    func testDecodesRegisteredTeam() throws {
        let json = """
        {
          "id": "p6",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "Registered team.",
          "media": [],
          "tags": [],
          "created_at": "2026-08-14T09:05:00Z",
          "team": {
            "handle": "hiboss",
            "display_name": "HiBoss",
            "avatar_url": "https://hiboss.example/api/progress/teams/hiboss/avatar.svg",
            "registered": true
          },
          "like_count": 3,
          "liked": true
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.team.handle, "hiboss")
        XCTAssertEqual(post.team.displayName, "HiBoss")
        XCTAssertEqual(post.team.avatarUrl, "https://hiboss.example/api/progress/teams/hiboss/avatar.svg")
        XCTAssertTrue(post.team.registered)
        XCTAssertEqual(post.likeCount, 3)
        XCTAssertTrue(post.liked)
    }

    func testDecodesUnregisteredTeam() throws {
        let json = """
        {
          "id": "p7",
          "project": "payments",
          "agent_id": "ak2",
          "agent_name": "worker-payments",
          "body": "Fallback identity.",
          "created_at": "2026-08-14T09:06:00Z",
          "team": {
            "handle": "payments",
            "display_name": "payments",
            "avatar_url": "https://hiboss.example/api/progress/teams/payments/avatar.svg",
            "registered": false
          }
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.team.handle, "payments")
        XCTAssertEqual(post.team.displayName, "payments")
        XCTAssertFalse(post.team.registered)
        XCTAssertFalse(post.team.avatarUrl.isEmpty)
    }

    func testDecodesPostWithNoLikes() throws {
        let json = """
        {
          "id": "p8",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "No likes yet.",
          "created_at": "2026-08-14T09:07:00Z",
          "team": {
            "handle": "hiboss",
            "display_name": "hiboss",
            "avatar_url": "https://hiboss.example/api/progress/teams/hiboss/avatar.svg",
            "registered": false
          }
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.likeCount, 0)
        XCTAssertFalse(post.liked)
        XCTAssertEqual(post.team.displayName, "hiboss")
    }

    func testDecodesAttributionWhenBothPresent() throws {
        let json = """
        {
          "id": "p9",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "Attributed post.",
          "created_at": "2026-08-14T09:08:00Z",
          "agent_label": "claude-code",
          "model": "claude-opus-5"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.agentLabel, "claude-code")
        XCTAssertEqual(post.model, "claude-opus-5")
    }

    func testDecodesAttributionWhenNeitherPresent() throws {
        let json = """
        {
          "id": "p10",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "Legacy post.",
          "created_at": "2026-08-14T09:09:00Z"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertNil(post.agentLabel)
        XCTAssertNil(post.model)
    }

    func testDecodesAttributionWhenOnlyAgentLabelPresent() throws {
        let json = """
        {
          "id": "p11",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "Agent only.",
          "created_at": "2026-08-14T09:10:00Z",
          "agent_label": "claude-code",
          "model": null
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.agentLabel, "claude-code")
        XCTAssertNil(post.model)
    }

    func testDecodesAttributionWhenOnlyModelPresent() throws {
        let json = """
        {
          "id": "p12",
          "project": "hiboss",
          "agent_id": "ak1",
          "agent_name": "hiboss-cli",
          "body": "Model only.",
          "created_at": "2026-08-14T09:11:00Z",
          "model": "gpt-5.6"
        }
        """
        let post = try JSONDecoder().decode(ProgressPost.self, from: Data(json.utf8))
        XCTAssertNil(post.agentLabel)
        XCTAssertEqual(post.model, "gpt-5.6")
    }
}
