// Env-gated fixtures so the attention UI can be looked at without a live boss.
// Exports: AttentionPreview for HIBOSS_ATTENTION_PREVIEW.
// Dependencies: SwiftUI, AttentionWorkspace, HibossKit HistoryMessage.

import HibossKit
import SwiftUI

enum AttentionPreview {
    static func historyIfRequested() -> [HistoryMessage]? {
        switch ProcessInfo.processInfo.environment["HIBOSS_ATTENTION_PREVIEW"] {
        case "1", "populated":
            let now = Date()
            return populated(now: now).map(\.message) + [
                attentionMessage(id: "preview-done", body: "Release verified. All checks passed.",
                    priority: "normal", options: ["Done"], createdAt: iso(now.addingTimeInterval(-3600)),
                    sessionLabel: "hiboss/main", sessionStatus: "idle", status: "replied")
            ]
        case "empty": return []
        default: return nil
        }
    }

    static func populated(now: Date) -> [AttentionItem] {
        let auto = attentionMessage(
            id: "preview-auto",
            body: """
            Please run the deployment from your terminal:
            SR_DEPLOY_HOST=preview-host ~/Develop/web3/project/deploy-smart-router.sh --skip-indexer
            The build and restart take about 10 minutes. Reply with the result and include any errors.
            """,
            priority: "normal",
            options: ["Ship", "Hold"],
            defaultOption: "Hold",
            expiresAt: iso(now.addingTimeInterval(95)),
            createdAt: iso(now.addingTimeInterval(-40)),
            sessionLabel: "hiboss/main",
            sessionStatus: "waiting"
        )
        let blocked = attentionMessage(
            id: "preview-blocked",
            body: "Blocked on the deploy approval.",
            priority: "normal",
            options: ["Approve", "Reject"],
            createdAt: iso(now.addingTimeInterval(-1800)),
            sessionLabel: "payments/hotfix",
            sessionStatus: "waiting"
        )
        let high = attentionMessage(
            id: "preview-high",
            body: "Nightly export finished with warnings.",
            priority: "high",
            options: ["Ignore", "Investigate"],
            createdAt: iso(now.addingTimeInterval(-300)),
            sessionLabel: "nightly-export",
            sessionStatus: "working"
        )
        return AttentionRanking.items(history: [high, blocked, auto], now: now)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func attentionMessage(
        id: MessageID,
        body: String,
        priority: String,
        options: [String],
        defaultOption: String? = nil,
        expiresAt: String? = nil,
        createdAt: String,
        sessionLabel: String?,
        sessionStatus: String?,
        status: String = "delivered"
    ) -> HistoryMessage {
        HistoryMessage(
            id: id,
            body: body,
            agentName: "Preview Agent",
            direction: "agent_to_boss",
            status: status,
            priority: priority,
            metadata: MessageMetadata(options: options, defaultOption: defaultOption),
            expiresAt: expiresAt,
            createdAt: createdAt,
            sessionId: id.rawValue,
            sessionLabel: sessionLabel,
            sessionStatus: sessionStatus
        )
    }
}
