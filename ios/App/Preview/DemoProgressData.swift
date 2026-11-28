// Sample progress posts for the demo, covering 1–4 item mosaics and aspect clamps.
// Media are bundled files: the demo never loads anything from the network.
// Exports: DemoProgressFixtures.
// Dependencies: Foundation, HibossKit ProgressPost.

import Foundation
import HibossKit

enum DemoProgressFixtures {
    private static let now = Date()

    static func iso(_ offset: TimeInterval, daysAgo: Int = 0) -> String {
        let start = Calendar.current.startOfDay(for: now)
        guard daysAgo > 0 else { return max(start, now.addingTimeInterval(offset)).ISO8601Format() }
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: start) ?? start
        return day.addingTimeInterval(12 * 60 * 60 + offset).ISO8601Format()
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
            id: "pp-wide", project: "storefront", agentId: "ak1", agentName: "storefront-cli",
            body: demoCopy(
                "Landscape screenshot wider than 2:1 — centre-cropped in the feed, full image on tap.",
                zh: "宽于 2:1 的横向截图：信息流里居中裁剪，点开看全图。"),
            media: [image(1015, width: 2000, height: 800, alt: "wide landscape screenshot")],
            tags: ["ios"], createdAt: iso(-60),
            team: .storefront, likeCount: 4, liked: false,
            agentLabel: "release-agent", model: "demo-model"
        ),
        ProgressPost(
            id: "pp-tall", project: "storefront", agentId: "ak1", agentName: "storefront-cli",
            body: demoCopy(
                "Portrait shot taller than 3:4 — clamped in the mosaic, full image on tap.",
                zh: "高于 3:4 的竖向截图：拼图里限高显示，点开看全图。"),
            media: [image(1016, width: 800, height: 1600, alt: "tall portrait screenshot")],
            createdAt: iso(-120, daysAgo: 1),
            team: .storefront, likeCount: 2, liked: false
        ),
        ProgressPost(
            id: "pp-two", project: "storefront", agentId: "ak1", agentName: "storefront-cli",
            body: demoCopy(
                "Two stills, equal columns, 16:9 group.",
                zh: "两张图，等宽两列，整体 16:9。"),
            media: [
                image(10, width: 800, height: 600, alt: "leading still"),
                image(11, width: 800, height: 600, alt: "trailing still"),
            ],
            createdAt: iso(-180, daysAgo: 1),
            team: .storefront, likeCount: 1, liked: false
        ),
        ProgressPost(
            id: "pp-three", project: "storefront", agentId: "ak1", agentName: "storefront-cli",
            body: demoCopy(
                "Three stills: one full-height lead, two stacked.",
                zh: "三张图：一张通高主图，两张上下排列。"),
            media: [
                image(12, width: 800, height: 1200, alt: "lead still"),
                image(13, width: 800, height: 600, alt: "top still"),
                image(14, width: 800, height: 600, alt: "bottom still"),
            ],
            createdAt: iso(-240, daysAgo: 1),
            team: .storefront, likeCount: 0, liked: false
        ),
        ProgressPost(
            id: "pp-four", project: "storefront", agentId: "ak1", agentName: "storefront-cli",
            body: demoCopy(
                "Four stills in a 2×2, 16:9 group.",
                zh: "四张图，2×2 排列，整体 16:9。"),
            media: [
                image(15, width: 800, height: 600, alt: "quad top leading"),
                image(16, width: 800, height: 600, alt: "quad top trailing"),
                image(17, width: 800, height: 600, alt: "quad bottom leading"),
                image(18, width: 800, height: 600, alt: "quad bottom trailing"),
            ],
            createdAt: iso(-300, daysAgo: 1),
            team: .storefront, likeCount: 8, liked: true
        ),
        ProgressPost(
            id: "pp-video", project: "storefront", agentId: "ak1", agentName: "storefront-cli",
            body: demoCopy(
                "Muted looping clip. Tap opens full screen; the speaker toggles sound.",
                zh: "静音循环短片。点按全屏播放，扬声器按钮开关声音。"),
            media: [
                ProgressMedia(
                    url: bundled("demo-box-clip", "mp4"),
                    kind: .video, contentType: "video/mp4", size: 512_000,
                    width: 1280, height: 720, durationMs: 15_000,
                    posterUrl: bundled("demo-coarse-grid"),
                    alt: "looping demo clip"
                ),
            ],
            createdAt: iso(-400, daysAgo: 1),
            team: .storefront, likeCount: 1, liked: false
        ),
        ProgressPost(
            id: "pp-nodim", project: "payments", agentId: "ak2", agentName: "worker-payments",
            body: demoCopy(
                "Retry chart after the gateway timeout — dimensions omitted on purpose.",
                zh: "网关超时后的重试曲线，故意省略了尺寸。"),
            media: [
                ProgressMedia(
                    url: bundled("demo-fine-grid"),
                    kind: .image, contentType: "image/jpeg", size: 40_000,
                    alt: "retry latency chart"
                ),
            ],
            tags: ["hotfix"], createdAt: iso(-1800, daysAgo: 2),
            team: .payments, likeCount: 0, liked: false
        ),
        ProgressPost(
            id: "pp-text", project: "payments", agentId: "ak2", agentName: "worker-payments",
            body: demoCopy(
                "Sandbox timeout reproduced. Waiting on the retry strategy decision.",
                zh: "沙盒超时已复现，正在等待重试策略的决定。"),
            createdAt: iso(-2400, daysAgo: 2),
            team: .payments, likeCount: 2, liked: false
        ),
    ]

    static let projects: [ProgressProject] = [
        ProgressProject(project: "storefront", count: 6, lastPostAt: iso(-60), agentId: "ak1"),
        ProgressProject(project: "payments", count: 2, lastPostAt: iso(-1800, daysAgo: 2), agentId: "ak2"),
    ]
}

private extension ProgressTeam {
    static let storefront = ProgressTeam(
        handle: "storefront", displayName: "Storefront",
        avatarUrl: DemoProgressFixtures.bundled("demo-coarse-grid"), registered: true
    )
    static let payments = ProgressTeam(
        handle: "payments", displayName: "payments",
        avatarUrl: DemoProgressFixtures.bundled("demo-fine-grid"), registered: false
    )
}
