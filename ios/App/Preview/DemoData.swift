// Demo backing data so the UI can be exercised without a live server.
// Exports: DemoBossAPI, DemoProgressAPI, and isDemoMode, gated by the HIBOSS_DEMO env var.
// Dependencies: HibossKit BossServing. Not used in normal (server-backed) runs.

import Foundation
import HibossKit

var isDemoMode: Bool {
    ProcessInfo.processInfo.environment["HIBOSS_DEMO"] == "1"
}

/// A static BossServing replaying sample decisions across a few agent sessions.
final class DemoBossAPI: BossServing, @unchecked Sendable {
    private var messages: [HistoryMessage]

    init() {
        messages = DemoFixtures.queue
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        let mode = ProcessInfo.processInfo.environment["HIBOSS_DEMO_CONNECTION"]
        if mode == "connecting" {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
        return AsyncThrowingStream { continuation in
            if mode == "failed" {
                continuation.finish(throwing: DemoConnectionError.failed)
                return
            }
            continuation.onTermination = { _ in }
        }
    }

    func fetchHistory() async throws -> [HistoryMessage] { messages }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return .accepted
        }
        let parent = messages[index]
        messages[index] = DemoFixtures.answered(parent)
        messages.append(DemoFixtures.bossReply(to: parent, choice: choice, source: "ios"))
        return .accepted
    }
}

private enum DemoConnectionError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "Couldn't reach the server." }
}

/// Sample history grouped into three sessions plus a direct message.
private enum DemoFixtures {
    static func iso(_ offset: TimeInterval) -> String {
        Date().addingTimeInterval(offset).ISO8601Format()
    }

    /// `HIBOSS_DEMO_EMPTY=1` drops live decisions so the all-clear strip can be screenshotted.
    static var queue: [HistoryMessage] {
        ProcessInfo.processInfo.environment["HIBOSS_DEMO_EMPTY"] == "1"
            ? messages.filter { !$0.isPendingDecision }
            : messages
    }

    static let messages: [HistoryMessage] = deploy + payments + data + direct

    static func answered(_ parent: HistoryMessage) -> HistoryMessage {
        HistoryMessage(
            id: parent.id, body: parent.body, agentName: parent.agentName,
            direction: parent.direction, status: "replied", priority: parent.priority,
            channel: parent.channel, mode: parent.mode, type: parent.type,
            replyTo: parent.replyTo, metadata: parent.metadata, expiresAt: parent.expiresAt,
            createdAt: parent.createdAt, sessionId: parent.sessionId,
            targetSessionId: parent.targetSessionId, sessionLabel: parent.sessionLabel,
            sessionBranch: parent.sessionBranch, sessionStatus: parent.sessionStatus
        )
    }

    static func bossReply(to parent: HistoryMessage, choice: String, source: String) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: "r-\(parent.id.rawValue)"), body: choice, agentName: parent.agentName,
            direction: "boss_to_agent", status: "sent", priority: "normal",
            channel: "api", mode: "async", replyTo: parent.id.rawValue,
            metadata: MessageMetadata(options: [], source: source),
            createdAt: Date().ISO8601Format(),
            sessionId: parent.sessionId, targetSessionId: parent.sessionId ?? parent.targetSessionId,
            sessionLabel: parent.sessionLabel, sessionBranch: parent.sessionBranch,
            sessionStatus: parent.sessionStatus
        )
    }

    private static let deploy: [HistoryMessage] = [
        HistoryMessage(
            id: "c0", body: "Ship the changelog to TestFlight tonight?",
            agentName: "orchestrator-01", direction: "agent_to_boss", status: "replied",
            priority: "high", channel: "discord", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(options: ["Ship", "Hold"]),
            expiresAt: nil, createdAt: iso(-120),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "working"
        ),
        HistoryMessage(
            id: "r0", body: "Ship",
            agentName: "orchestrator-01", direction: "boss_to_agent", status: "sent",
            priority: "normal", channel: "telegram", mode: "async",
            replyTo: "c0",
            metadata: MessageMetadata(options: [], source: "telegram"),
            createdAt: iso(-90),
            targetSessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "working"
        ),
        HistoryMessage(
            id: "c1", body: "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?",
            agentName: "orchestrator-01", direction: "agent_to_boss", status: "delivered",
            priority: "critical", channel: "discord", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(options: ["Approve", "Reject"]),
            expiresAt: iso(95), createdAt: iso(-40),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "waiting"
        ),
        HistoryMessage(
            id: "h1", body: "Deployment to staging complete. All 214 tests green.",
            agentName: "orchestrator-01", direction: "agent_to_boss", status: "replied",
            priority: "normal", channel: "discord", mode: "async", type: "task_update",
            metadata: MessageMetadata(options: [], files: ["server/migrations/003.sql", "cli/src/commands/send.rs"]),
            expiresAt: nil, createdAt: iso(-1800),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "waiting"
        ),
    ]

    private static let payments: [HistoryMessage] = [
        HistoryMessage(
            id: "c2", body: "Stripe timed out 3× in a row. Pick a retry strategy:",
            agentName: "worker-payments", direction: "agent_to_boss", status: "delivered",
            priority: "high", channel: "telegram", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(options: [
                "Retry now (same gateway)", "Retry with exponential backoff", "Fail over to Adyen",
            ]),
            expiresAt: iso(760), createdAt: iso(-90),
            sessionId: "sess-pay", sessionLabel: "payments-hotfix", sessionBranch: "fix/stripe-retry",
            sessionStatus: "blocked"
        ),
        HistoryMessage(
            id: "h2", body: "Reproduced the timeout on the sandbox key — it's gateway-side latency.",
            agentName: "worker-payments", direction: "agent_to_boss", status: "replied",
            priority: "normal", channel: "telegram", mode: "async",
            metadata: nil, expiresAt: nil, createdAt: iso(-600),
            sessionId: "sess-pay", sessionLabel: "payments-hotfix", sessionBranch: "fix/stripe-retry",
            sessionStatus: "blocked"
        ),
    ]

    private static let data: [HistoryMessage] = [
        HistoryMessage(
            id: "c3", body: "Need read-only staging DB credentials to continue the export.",
            agentName: "worker-data", direction: "agent_to_boss", status: "delivered",
            priority: "normal", channel: "api", mode: "async", type: "steer_command",
            metadata: MessageMetadata(options: ["Provide", "Later"]),
            expiresAt: nil, createdAt: iso(-300),
            sessionId: "sess-data", sessionLabel: "nightly-export", sessionBranch: "main",
            sessionStatus: "working"
        ),
    ]

    private static let direct: [HistoryMessage] = [
        HistoryMessage(
            id: "d1", body: "Heads up — I paused the backfill until you confirm the credentials above.",
            agentName: "worker-data", direction: "agent_to_boss", status: "delivered",
            priority: "low", channel: "api", mode: "async",
            metadata: nil, expiresAt: nil, createdAt: iso(-120)
        ),
    ]
}

/// Sample progress posts so the 进展 tab can be exercised without a live server.
final class DemoProgressAPI: ProgressServing, @unchecked Sendable {
    func progressFeed(project: String?, limit: Int, before: ProgressCursor?) async throws -> ProgressFeedPage {
        var posts = DemoProgressFixtures.posts
        if let project { posts = posts.filter { $0.project == project } }
        if let before {
            posts = posts.filter {
                $0.createdAt < before.createdAt || ($0.createdAt == before.createdAt && $0.id < before.id)
            }
        }
        let page = Array(posts.prefix(limit))
        let next = posts.count > limit ? page.last.map { ProgressCursor(createdAt: $0.createdAt, id: $0.id) } : nil
        return ProgressFeedPage(posts: page, nextCursor: next)
    }

    func progressProjects() async throws -> [ProgressProject] {
        DemoProgressFixtures.projects
    }

    func deleteProgressPost(id _: String) async throws {}
}

private enum DemoProgressFixtures {
    static func iso(_ offset: TimeInterval) -> String {
        Date().addingTimeInterval(offset).ISO8601Format()
    }

    static let posts: [ProgressPost] = [
        ProgressPost(
            id: "pp1", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            sessionId: "sess-progress",
            body: "Shipped the progress feed. Migration + 4 endpoints. Pull-to-refresh, no push.",
            tags: ["release"], createdAt: iso(-90)
        ),
        ProgressPost(
            id: "pp2", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Native 进展 tab — system List, semantic colours, one looping player at a time.",
            media: [
                ProgressMedia(
                    url: "https://picsum.photos/id/1015/1200/800",
                    kind: .image, contentType: "image/jpeg", size: 84_000,
                    width: 1200, height: 800, alt: "screenshot of the new tab"
                ),
            ],
            tags: ["ios"], createdAt: iso(-400)
        ),
        ProgressPost(
            id: "pp3", project: "hiboss", agentId: "ak1", agentName: "hiboss-cli",
            body: "Short muted looping clip of the feed scrolling. Tap to unmute.",
            media: [
                ProgressMedia(
                    url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlips.mp4",
                    kind: .video, contentType: "video/mp4", size: 512_000,
                    width: 1280, height: 720, durationMs: 15_000,
                    posterUrl: "https://picsum.photos/id/1018/1280/720",
                    alt: "looping demo clip"
                ),
            ],
            createdAt: iso(-900)
        ),
        ProgressPost(
            id: "pp4", project: "payments", agentId: "ak2", agentName: "worker-payments",
            body: "Retry chart after the Stripe timeout — dimensions omitted on purpose.",
            media: [
                ProgressMedia(
                    url: "https://picsum.photos/id/180/900/500",
                    kind: .image, contentType: "image/jpeg", size: 40_000,
                    alt: "retry latency chart"
                ),
            ],
            tags: ["hotfix"], createdAt: iso(-1800)
        ),
        ProgressPost(
            id: "pp5", project: "payments", agentId: "ak2", agentName: "worker-payments",
            body: "Sandbox timeout reproduced. Waiting on the retry strategy decision.",
            createdAt: iso(-2400)
        ),
    ]

    static let projects: [ProgressProject] = [
        ProgressProject(project: "hiboss", count: 3, lastPostAt: iso(-90), agentId: "ak1"),
        ProgressProject(project: "payments", count: 2, lastPostAt: iso(-1800), agentId: "ak2"),
    ]
}
