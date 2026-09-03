// Env-gated fixtures so the attention UI can be looked at without a live boss.
// Exports: AttentionPreview for HIBOSS_ATTENTION_PREVIEW.
// Dependencies: SwiftUI, AttentionWorkspace, HibossKit HistoryMessage.

import HibossKit
import SwiftUI

enum AttentionPreview {
    /// `HIBOSS_ATTENTION_PREVIEW=populated|empty` swaps the main window content.
    @MainActor
    static func workspaceIfRequested() -> AnyView? {
        switch ProcessInfo.processInfo.environment["HIBOSS_ATTENTION_PREVIEW"] {
        case "1", "populated":
            return AnyView(AttentionPreviewHost(items: populated(now: Date())))
        case "empty":
            return AnyView(AttentionPreviewHost(items: []))
        default:
            return nil
        }
    }

    static func populated(now: Date) -> [AttentionItem] {
        let auto = attentionMessage(
            id: "preview-auto",
            body: "Ship the attention window tonight?",
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
        sessionStatus: String?
    ) -> HistoryMessage {
        HistoryMessage(
            id: id,
            body: body,
            agentName: "Preview Agent",
            direction: "agent_to_boss",
            status: "delivered",
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

private struct AttentionPreviewHost: View {
    let items: [AttentionItem]
    @State private var selection: MessageID?

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    L("Nothing needs you"),
                    systemImage: "checkmark.circle",
                    description: Text(L("You're clear. Agents will show up here when they need a decision."))
                )
            } else {
                AttentionWorkspace(
                    items: items,
                    now: Date(),
                    selection: $selection,
                    onChoose: { _, _ in }
                )
            }
        }
        .navigationTitle(L("Needs You"))
    }
}
