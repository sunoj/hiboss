// Agent attachment fixtures with a bundled image for deterministic native UI coverage.
// Exports: DemoMessageAttachments, selected with HIBOSS_DEMO_ATTACHMENTS=1.
// Dependencies: Foundation, HibossKit and the bundled demo PNG.

import Foundation
import HibossKit

enum DemoMessageAttachments {
    static let imageURL = "https://example.com/attachments/release-banner.png"
    static let fileURL = "https://example.com/attachments/release-notes.pdf"

    static func queue(fallback: [HistoryMessage]) -> [HistoryMessage] {
        let mode = ProcessInfo.processInfo.environment["HIBOSS_DEMO_ATTACHMENTS"] ?? ""
        guard ["1", "failure"].contains(mode) else {
            return fallback
        }
        return [
            message(id: "attachment-image", url: imageURL),
            message(id: "attachment-file", url: fileURL),
            message(id: "attachment-decision", url: imageURL, decision: true),
        ]
    }

    private static func message(id: MessageID, url: String, decision: Bool = false) -> HistoryMessage {
        HistoryMessage(
            id: id, body: decision ? "Approve the release banner?" : "The release attachment is ready.",
            agentName: "worker-design", direction: "agent_to_boss", status: "delivered",
            priority: "normal", channel: "api", mode: decision ? "blocking" : "async",
            type: decision ? "approval_request" : "task_update",
            metadata: MessageMetadata(options: decision ? ["Approve", "Revise"] : [], fileURL: url),
            createdAt: Date().addingTimeInterval(-60).ISO8601Format(),
            sessionId: "sess-deploy", sessionLabel: "prod-release", sessionStatus: "working"
        )
    }

    static func imageResource(for url: URL) -> String {
        guard isDemoMode, url.absoluteString == imageURL else { return url.absoluteString }
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_ATTACHMENTS"] == "failure" {
            // An invalid image resource exercises the unavailable state without a network dependency.
            return "https://["
        }
        return Bundle.main.url(forResource: "demo-coarse-grid", withExtension: "png")?.absoluteString
            ?? url.absoluteString
    }
}
