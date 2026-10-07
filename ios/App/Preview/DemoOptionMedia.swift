// Demo option images, bundled so screenshots and UI tests never need the network.
// Exports: DemoOptionMedia (HIBOSS_DEMO_OPTION_MEDIA=1) and DemoOptionMediaFixtures
// (pending, resolved or automatic). Dependencies: Foundation, bundled PNGs, HibossKit.

import Foundation
import HibossKit

enum DemoOptionMedia {
    static var images: [OptionMedia] {
        images(enabled: ProcessInfo.processInfo.environment["HIBOSS_DEMO_OPTION_MEDIA"] == "1")
    }

    static func images(enabled: Bool) -> [OptionMedia] {
        guard enabled else { return [] }
        return [
            image(label: "Coarse grid", resource: "demo-coarse-grid"),
            image(label: "Fine grid", resource: "demo-fine-grid"),
        ].compactMap { $0 }
    }

    static func image(label: String, resource: String) -> OptionMedia? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png") else { return nil }
        return OptionMedia(label: label, url: url.absoluteString)
    }
}

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
                    DemoOptionMedia.image(label: "Mountain view", resource: "demo-fine-grid"),
                    DemoOptionMedia.image(label: "Coastal view", resource: "demo-coarse-grid"),
                ].compactMap { $0 }, isExpired: automatic, defaultOption: "Mountain view"
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
