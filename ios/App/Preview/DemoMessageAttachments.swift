// Agent attachment fixtures with a bundled image for deterministic native UI coverage.
// Exports: DemoMessageAttachments, selected with HIBOSS_DEMO_ATTACHMENTS=1.
// Dependencies: Foundation, HibossKit and the bundled demo PNG.

import Foundation
import HibossKit

enum DemoMessageAttachments {
    static let imageURL = "https://example.com/attachments/release-banner.png"
    static let fileURL = "https://example.com/attachments/release-notes.pdf"
    static let markdownURL = "https://example.com/attachments/release-notes.md"
    static let videoURL = "https://example.com/attachments/release-demo.mp4"

    static func queue(fallback: [HistoryMessage]) -> [HistoryMessage] {
        let mode = ProcessInfo.processInfo.environment["HIBOSS_DEMO_ATTACHMENTS"] ?? ""
        if mode == "video" { return [message(id: "attachment-video", url: videoURL)] }
        if ["markdown", "markdown-multiline", "markdown-error"].contains(mode) {
            return [message(id: "attachment-file", url: markdownURL)]
        }
        guard ["1", "failure"].contains(mode) else {
            return fallback
        }
        return [
            message(id: "attachment-image", url: imageURL),
            message(id: "attachment-file", url: fileURL),
            message(id: "attachment-decision", url: imageURL, decision: true),
        ]
    }

    static func previewSource(for url: URL) async throws -> String? {
        if isDemoMode, ProcessInfo.processInfo.environment["HIBOSS_DEMO_ATTACHMENTS"] == "markdown-error" {
            try await DemoDelay.wait("MEDIA")
            throw MarkdownAttachmentDocument.DocumentError.unavailable
        }
        return markdownSource(for: url)
    }

    static func markdownSource(for url: URL) -> String? {
        let mode = ProcessInfo.processInfo.environment["HIBOSS_DEMO_ATTACHMENTS"] ?? ""
        guard isDemoMode, url.absoluteString == markdownURL,
              ["markdown", "markdown-multiline"].contains(mode) else { return nil }
        if mode == "markdown-multiline" { return multilineTable }
        let image = Bundle.main.url(forResource: "demo-coarse-grid", withExtension: "png")!
        return """
        # Release notes

        **Ready** for review.

        ![Document image](\(image.absoluteString) "Release banner")

        | Package | Budget |
        | --- | ---: |
        | Alpha | 345 |

        ```sh
        swift test
        ```
        """
    }

    private static var multilineTable: String {
        let descriptions = [
            "Client response is interpreted as complete before every required source "
                + "has returned its current snapshot.",
            "Recorded refresh threshold uses the first callback while the actual result "
                + "arrives after reconciliation finishes.",
            "Passive connection state is shown as current data even when the stored snapshot "
                + "is waiting for an update.",
        ]
        let rows = descriptions.enumerated().map { index, description in
            ["A\(index + 1)", "REPRODUCIBLE", description, "source-\(index + 1).swift:42"]
                .joined(separator: " | ")
        }
        return (["# Table layout report", "", "| ID | Occurrence | Defect | Source |",
                 "| --- | --- | --- | --- |"] + rows + ["", "The table rows remain separate."])
            .joined(separator: "\n")
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

    static func mediaResource(for url: URL) -> String {
        if isDemoMode, url.absoluteString == videoURL {
            return Bundle.main.url(forResource: "demo-box-clip", withExtension: "mp4")?.absoluteString
                ?? url.absoluteString
        }
        guard isDemoMode, url.absoluteString == imageURL else { return url.absoluteString }
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_ATTACHMENTS"] == "failure" {
            // An invalid image resource exercises the unavailable state without a network dependency.
            return Bundle.main.bundleURL.appendingPathComponent("missing-image.png").absoluteString
        }
        return Bundle.main.url(forResource: "demo-coarse-grid", withExtension: "png")?.absoluteString
            ?? url.absoluteString
    }
}
