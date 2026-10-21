// Sample progress posts for the demo, covering 1–4 item mosaics and aspect clamps.
// Media are bundled files: the demo never loads anything from the network.
// Exports: DemoProgressFixtures.
// Dependencies: Foundation, HibossKit ProgressPost.

import Foundation
import HibossKit

enum DemoProgressFixtures {
    static func iso(_ offset: TimeInterval) -> String {
        Date().addingTimeInterval(offset).ISO8601Format()
    }

    /// A bundled demo file; alternating grids keep neighbouring mosaic cells distinct.
    static func bundled(_ resource: String, _ ext: String = "png") -> String {
        Bundle.main.url(forResource: resource, withExtension: ext)?.absoluteString ?? ""
    }

    static func image(_ id: Int, width: Int, height: Int, alt: String? = nil) -> ProgressMedia {
        ProgressMedia(
            url: bundled(id.isMultiple(of: 2) ? "demo-fine-grid" : "demo-coarse-grid"),
            kind: .image, contentType: "image/jpeg", size: 80_000,
            width: width, height: height, alt: alt
        )
    }

    static let posts: [ProgressPost] = [
        ProgressPost(
            id: "pp-wide", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Landscape screenshot wider than 2:1 — centre-cropped in the feed, full image on tap.",
            media: [image(1015, width: 2000, height: 800, alt: "wide landscape screenshot")],
            tags: ["ios"], createdAt: iso(-60),
            team: .hiboss, likeCount: 4, liked: false,
            agentLabel: "claude-code", model: "claude-opus-5"
        ),
        ProgressPost(
            id: "pp-tall", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Portrait shot taller than 3:4 — clamped in the mosaic, full image on tap.",
            media: [image(1016, width: 800, height: 1600, alt: "tall portrait screenshot")],
            createdAt: iso(-120),
            team: .hiboss, likeCount: 2, liked: false
        ),
        ProgressPost(
            id: "pp-two", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Two stills, equal columns, 16:9 group.",
            media: [
                image(10, width: 800, height: 600, alt: "leading still"),
                image(11, width: 800, height: 600, alt: "trailing still"),
            ],
            createdAt: iso(-180),
            team: .hiboss, likeCount: 1, liked: false
        ),
        ProgressPost(
            id: "pp-three", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Three stills: one full-height lead, two stacked.",
            media: [
                image(12, width: 800, height: 1200, alt: "lead still"),
                image(13, width: 800, height: 600, alt: "top still"),
                image(14, width: 800, height: 600, alt: "bottom still"),
            ],
            createdAt: iso(-240),
            team: .hiboss, likeCount: 0, liked: false
        ),
        ProgressPost(
            id: "pp-four", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Four stills in a 2×2, 16:9 group.",
            media: [
                image(15, width: 800, height: 600, alt: "quad top leading"),
                image(16, width: 800, height: 600, alt: "quad top trailing"),
                image(17, width: 800, height: 600, alt: "quad bottom leading"),
                image(18, width: 800, height: 600, alt: "quad bottom trailing"),
            ],
            createdAt: iso(-300),
            team: .hiboss, likeCount: 8, liked: true
        ),
        ProgressPost(
            id: "pp-video", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Muted looping clip. Tap opens full screen; the speaker toggles sound.",
            media: [
                ProgressMedia(
                    url: bundled("demo-box-clip", "mp4"),
                    kind: .video, contentType: "video/mp4", size: 512_000,
                    width: 1280, height: 720, durationMs: 15_000,
                    posterUrl: bundled("demo-coarse-grid"),
                    alt: "looping demo clip"
                ),
            ],
            createdAt: iso(-400),
            team: .hiboss, likeCount: 1, liked: false
        ),
        ProgressPost(
            id: "pp-nodim", project: "payments", agentId: "ak2", agentName: "worker-payments",
            body: "Retry chart after the Stripe timeout — dimensions omitted on purpose.",
            media: [
                ProgressMedia(
                    url: bundled("demo-fine-grid"),
                    kind: .image, contentType: "image/jpeg", size: 40_000,
                    alt: "retry latency chart"
                ),
            ],
            tags: ["hotfix"], createdAt: iso(-1800),
            team: .payments, likeCount: 0, liked: false
        ),
        ProgressPost(
            id: "pp-text", project: "payments", agentId: "ak2", agentName: "worker-payments",
            body: "Sandbox timeout reproduced. Waiting on the retry strategy decision.",
            createdAt: iso(-2400),
            team: .payments, likeCount: 2, liked: false
        ),
    ]

    static let projects: [ProgressProject] = [
        ProgressProject(project: "hiboss", count: 6, lastPostAt: iso(-60), agentId: "ak1"),
        ProgressProject(project: "payments", count: 2, lastPostAt: iso(-1800), agentId: "ak2"),
    ]
}

private extension ProgressTeam {
    static let hiboss = ProgressTeam(
        handle: "hiboss", displayName: "HiBoss",
        avatarUrl: DemoProgressFixtures.bundled("demo-coarse-grid"), registered: true
    )
    static let payments = ProgressTeam(
        handle: "payments", displayName: "payments",
        avatarUrl: DemoProgressFixtures.bundled("demo-fine-grid"), registered: false
    )
}
