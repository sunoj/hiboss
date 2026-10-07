// Demo backing data so the UI can be exercised without a live server.
// Exports: DemoBossAPI and isDemoMode.
// Dependencies: HibossKit BossServing. Not used in normal runs.

import Foundation
import HibossKit

var isDemoMode: Bool {
    ProcessInfo.processInfo.environment["HIBOSS_DEMO"] == "1"
}

/// A static BossServing replaying sample decisions across a few agent sessions.
final class DemoBossAPI: BossServing, RequiredInputServing, SessionStreamServing, @unchecked Sendable {
    var messages: [HistoryMessage]
    var sessionFetchCount = 0

    init() {
        messages = ProcessInfo.processInfo.environment["HIBOSS_DEMO_TEXT_ASK"] == "1"
            ? [DemoTextAsk.message] : DemoOptionMediaFixtures.queue(fallback: DemoFixtures.queue)
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

    private let started = Date()

    /// `HIBOSS_DEMO_REFRESH_FAILS=1`: launch-time fetches succeed; any after five seconds fail.
    func fetchHistory() async throws -> [HistoryMessage] {
        if Date().timeIntervalSince(started) > 5 { try await DemoDelay.wait("REFRESH") }
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_REFRESH_FAILS"] == "1",
           Date().timeIntervalSince(started) > 5 {
            throw DemoConnectionError.failed
        }
        let rawDelay = ProcessInfo.processInfo.environment["HIBOSS_DEMO_HISTORY_DELAY_MS"] ?? "0"
        let delay = UInt64(rawDelay) ?? 0
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        return messages
    }

    func fetchRequiredInputs() async throws -> [HistoryMessage] {
        if Date().timeIntervalSince(started) > 5 { try await DemoDelay.wait("REFRESH") }
        try await DemoDelay.wait("REQUESTS")
        return messages.filter { $0.isPendingDecision || AttentionModel.needsTextReply($0) }
    }

    func requiredInputStream() async -> AsyncThrowingStream<RequiredInputEvent, Error> {
        try? await DemoDelay.wait("REQUESTS_READY")
        let mode = ProcessInfo.processInfo.environment["HIBOSS_DEMO_REQUESTS_STREAM"]
        return AsyncThrowingStream { continuation in
            if mode == "ends" { continuation.finish(); return }
            if mode != "silent" { continuation.yield(.ready) }
            continuation.onTermination = { _ in }
        }
    }

    /// `HIBOSS_DEMO_REPLY_DELAY_MS` holds each reply in flight so its disabled state can be seen.
    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome {
        let delay = Int(ProcessInfo.processInfo.environment["HIBOSS_DEMO_REPLY_DELAY_MS"] ?? "") ?? 0
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_REPLY_FAILS"] == "1" {
            throw DemoConnectionError.failed
        }
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
    var errorDescription: String? { String(localized: "Couldn't reach the server.") }
}

/// Sample history grouped into three sessions plus a direct message.
private enum DemoFixtures {
    static func iso(_ offset: TimeInterval) -> String {
        let stable = ProcessInfo.processInfo.environment["HIBOSS_DEMO_STABLE_DEADLINES"] == "1"
        let reference = stable && offset > 0 ? Date().addingTimeInterval(20 * 60) : Date()
        return reference.addingTimeInterval(offset).ISO8601Format()
    }

    /// `HIBOSS_DEMO_EMPTY=1` drops live decisions so the all-clear strip can be screenshotted.
    static var queue: [HistoryMessage] {
        ProcessInfo.processInfo.environment["HIBOSS_DEMO_EMPTY"] == "1"
            ? messages.filter { !$0.isPendingDecision }
            : messages
    }

    static let messages: [HistoryMessage] = deploy + payments + data + direct
        + [
            bossReply(
                to: data[1], choice: "Keep current key", source: "api", automatic: true, at: iso(-6_600))
        ]

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

    /// `automatic` is the historical timeout shape: `auto_default: true` with source `api`.
    static func bossReply(
        to parent: HistoryMessage, choice: String, source: String, automatic: Bool = false,
        at created: String = Date().ISO8601Format()
    ) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: "r-\(parent.id.rawValue)"), body: choice, agentName: parent.agentName,
            direction: "boss_to_agent", status: "sent", priority: "normal",
            channel: "api", mode: "async", replyTo: parent.id.rawValue,
            metadata: MessageMetadata(options: [], source: source, isAutoDefault: automatic),
            createdAt: created,
            sessionId: parent.sessionId, targetSessionId: parent.sessionId ?? parent.targetSessionId,
            sessionLabel: parent.sessionLabel, sessionBranch: parent.sessionBranch,
            sessionStatus: parent.sessionStatus
        )
    }

    private static let deploy: [HistoryMessage] = [
        HistoryMessage(
            id: "c5", body: "Which release banner grid should ship — coarse blocks or a fine weave?",
            agentName: "worker-design", direction: "agent_to_boss", status: "delivered",
            priority: "high", channel: "telegram", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(
                options: ["Coarse grid", "Fine grid"],
                optionMedia: DemoOptionMedia.images,
                defaultOption: "Coarse grid",
                content: "Choose the density for the banner layout."
            ),
            expiresAt: iso(90), createdAt: iso(-60),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "blocked"
        ),
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
            id: "c6", body: "Page the on-call for the staging 5xx spike?",
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
            replyTo: "c6",
            metadata: MessageMetadata(options: [], source: "macos"),
            createdAt: iso(-179_900),
            targetSessionId: "sess-deploy", sessionLabel: "prod-release", sessionBranch: "release/v2.4",
            sessionStatus: "working"
        ),
        HistoryMessage(
            id: "c1",
            body:
                "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?",
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
            metadata: MessageMetadata(
                options: [], files: ["server/migrations/003.sql", "cli/src/commands/send.rs"]),
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
                ], defaultOption: "Retry with exponential backoff",
                content: "The agent is waiting for a retry policy."),
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
        // Timed out: the server recorded its default as a `system` reply.
        HistoryMessage(
            id: "a1", body: "Rotate the export bucket key before tonight's run?",
            agentName: "worker-data", direction: "agent_to_boss", status: "replied",
            priority: "normal", channel: "api", mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(options: ["Rotate now", "Keep current key"], isExpired: true,
                                      defaultOption: "Keep current key"),
            expiresAt: iso(-6_600), createdAt: iso(-7_200),
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
