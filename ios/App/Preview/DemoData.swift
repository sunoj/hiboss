// Demo backing data so the UI can be exercised without a live server.
// Exports: DemoBossAPI (incl. HomeServing), DemoProgressAPI, and isDemoMode.
// Dependencies: HibossKit BossServing/HomeServing. Not used in normal runs.

import Foundation
import HibossKit

var isDemoMode: Bool {
    ProcessInfo.processInfo.environment["HIBOSS_DEMO"] == "1"
}

/// A static BossServing replaying sample decisions across a few agent sessions.
final class DemoBossAPI: BossServing, SessionStreamServing, HomeServing, @unchecked Sendable {
    private var messages: [HistoryMessage]

    init() {
        messages = DemoFixtures.queue
    }

    func fetchHome() async throws -> HomeDashboard {
        DemoHomeFixtures.dashboard
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

    func fetchSessionEvents(
        sessionID: String,
        after: Int?,
        limit: Int
    ) async throws -> SessionEventsPage {
        let all = DemoSessionStream.events(for: sessionID, from: messages)
        let start = (after ?? -1) + 1
        let slice = all.filter { $0.sequence >= start }.prefix(limit)
        let events = Array(slice)
        return SessionEventsPage(
            events: events,
            nextAfter: events.last?.sequence,
            resync: false
        )
    }

    func sessionEventStream(
        sessionID: String,
        after: Int
    ) async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}

private enum DemoConnectionError: Error, LocalizedError {
    case failed
    var errorDescription: String? { String(localized: "Couldn't reach the server.") }
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
            id: "c4", body: "Merge the payments hotfix to main?",
            agentName: "orchestrator-01", direction: "agent_to_boss", status: "replied",
            priority: "high", channel: "discord", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(options: ["Merge", "Hold"]),
            createdAt: iso(-90_000),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "working"
        ),
        HistoryMessage(
            id: "r4", body: "Merge",
            agentName: "orchestrator-01", direction: "boss_to_agent", status: "sent",
            priority: "normal", channel: "api", mode: "async",
            replyTo: "c4",
            metadata: MessageMetadata(options: [], source: "ios"),
            createdAt: iso(-89_900),
            targetSessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "working"
        ),
        HistoryMessage(
            id: "c5", body: "Page the on-call for the staging 5xx spike?",
            agentName: "orchestrator-01", direction: "agent_to_boss", status: "replied",
            priority: "normal", channel: "api", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(options: ["Page", "Later"]),
            createdAt: iso(-180_000),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "working"
        ),
        HistoryMessage(
            id: "r5", body: "Later",
            agentName: "orchestrator-01", direction: "boss_to_agent", status: "sent",
            priority: "normal", channel: "api", mode: "async",
            replyTo: "c5",
            metadata: MessageMetadata(options: [], source: "macos"),
            createdAt: iso(-179_900),
            targetSessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "working"
        ),
        HistoryMessage(
            id: "c1", body: "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?",
            agentName: "orchestrator-01", direction: "agent_to_boss", status: "delivered",
            priority: "critical", channel: "discord", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(
                options: ["Approve", "Reject"], defaultOption: "Reject",
                content: "The migration cannot be undone once it starts."
            ),
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
            ], defaultOption: "Retry with exponential backoff", content: "The agent is waiting for a retry policy."),
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
            sessionStatus: "waiting"
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
    private var posts = DemoProgressFixtures.posts

    func progressFeed(project: String?, limit: Int, before: ProgressCursor?) async throws -> ProgressFeedPage {
        var posts = self.posts
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

    func likeProgressPost(id: String) async throws -> ProgressLikeState {
        applyLike(id: id, liked: true)
    }

    func unlikeProgressPost(id: String) async throws -> ProgressLikeState {
        applyLike(id: id, liked: false)
    }

    private func applyLike(id: String, liked: Bool) -> ProgressLikeState {
        guard let index = posts.firstIndex(where: { $0.id == id }) else {
            return ProgressLikeState(likeCount: 0, liked: liked)
        }
        let current = posts[index]
        let count = current.liked == liked
            ? current.likeCount
            : max(0, current.likeCount + (liked ? 1 : -1))
        posts[index] = current.withLike(count: count, liked: liked)
        return ProgressLikeState(likeCount: count, liked: liked)
    }
}
