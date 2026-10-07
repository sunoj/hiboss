// Option-image decisions for demo UI coverage of pending, chosen and timeout states.
// Exports: DemoOptionMediaFixtures, selected with HIBOSS_DEMO_OPTION_MEDIA.
// Dependencies: Foundation, HibossKit; normal demo history is preserved unless selected.

import Foundation
import HibossKit

enum DemoOptionMediaFixtures {
    static func queue(fallback: [HistoryMessage]) -> [HistoryMessage] {
        let state = ProcessInfo.processInfo.environment["HIBOSS_DEMO_OPTION_MEDIA"] ?? ""
        guard ["pending", "resolved", "automatic"].contains(state) else { return fallback }
        let pending = state == "pending"
        let automatic = state == "automatic"
        let message = HistoryMessage(
            id: "media-decision", body: "Which landscape should lead the release?",
            agentName: "worker-design", direction: "agent_to_boss",
            status: pending ? "delivered" : "replied", priority: "high", channel: "api",
            mode: "blocking", type: "approval_request",
            metadata: MessageMetadata(
                options: [" Coastal view ", "Mountain view"], optionMedia: [
                    OptionMedia(label: "Mountain view", url: "https://picsum.photos/id/1016/800/600"),
                    OptionMedia(label: "Coastal view", url: "https://picsum.photos/id/10/800/600"),
                ], isExpired: automatic, defaultOption: "Mountain view"
            ),
            createdAt: Date().addingTimeInterval(-120).ISO8601Format(),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionStatus: "working"
        )
        guard !pending else { return [message] }
        let reply = HistoryMessage(
            id: "media-reply", body: automatic ? "Mountain view" : "Coastal view",
            agentName: "worker-design", direction: "boss_to_agent", status: "sent",
            priority: "normal", channel: "api", mode: "async", replyTo: message.id.rawValue,
            metadata: MessageMetadata(options: [], source: "ios", isAutoDefault: automatic),
            createdAt: Date().addingTimeInterval(-60).ISO8601Format(),
            targetSessionId: "sess-deploy", sessionLabel: "prod-release", sessionStatus: "working"
        )
        return [message, reply]
    }
}
