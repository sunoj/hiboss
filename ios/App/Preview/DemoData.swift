// Demo backing data so the UI can be exercised without a live server.
// Exports: DemoBossAPI and isDemoMode, gated by the HIBOSS_DEMO env var.
// Dependencies: HibossKit BossServing. Not used in normal (server-backed) runs.

import Foundation
import HibossKit

var isDemoMode: Bool {
    ProcessInfo.processInfo.environment["HIBOSS_DEMO"] == "1"
}

/// A static BossServing that replays the three sample decisions from the design.
final class DemoBossAPI: BossServing, @unchecked Sendable {
    private let messages: [HistoryMessage]

    init() {
        func iso(_ offset: TimeInterval) -> String {
            Date().addingTimeInterval(offset).ISO8601Format()
        }
        messages = [
            HistoryMessage(
                id: "c1", body: "Production deploy will DROP 3 history tables (orders_2023 +2), irreversible. Run migration?",
                agentName: "orchestrator-01", direction: "agent_to_boss", status: "delivered",
                priority: "critical", channel: "discord", mode: "blocking",
                metadata: MessageMetadata(options: ["Approve", "Reject"]),
                expiresAt: iso(252), createdAt: iso(-40)
            ),
            HistoryMessage(
                id: "c2", body: "Stripe timed out 3× in a row. Pick a retry strategy:",
                agentName: "worker-payments", direction: "agent_to_boss", status: "delivered",
                priority: "high", channel: "telegram", mode: "blocking",
                metadata: MessageMetadata(options: [
                    "Retry now (same gateway)", "Retry with exponential backoff", "Fail over to Adyen",
                ]),
                expiresAt: iso(760), createdAt: iso(-90)
            ),
            HistoryMessage(
                id: "c3", body: "Need read-only staging DB credentials to continue the export.",
                agentName: "worker-data", direction: "agent_to_boss", status: "delivered",
                priority: "normal", channel: "api", mode: "async",
                metadata: MessageMetadata(options: ["Provide", "Later"]),
                expiresAt: nil, createdAt: iso(-300)
            ),
            HistoryMessage(
                id: "h1", body: "Deployment to staging complete. All 214 tests green.",
                agentName: "orchestrator-01", direction: "agent_to_boss", status: "replied",
                priority: "normal", channel: "discord", mode: "async",
                metadata: nil, expiresAt: nil, createdAt: iso(-1800)
            ),
        ]
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func fetchHistory() async throws -> [HistoryMessage] { messages }

    func reply(to messageID: MessageID, with choice: String) async throws -> ReplyOutcome { .accepted }
}
