// Targeted message lookup for demo-mode notification deep links.
// Exports: targeted fetches and message-detail fixtures.
// Dependencies: Foundation process environment, DemoBossAPI, and HibossKit.

import Foundation
import HibossKit

extension DemoBossAPI {
    func messageDetail(for messageID: MessageID) -> MessageDetail? {
        guard let message = messages.first(where: { $0.id == messageID }) else { return nil }
        let replies = messages.filter { $0.replyTo == messageID.rawValue }
        return MessageDetail(message: message, replies: replies)
    }

    func fetchMessage(_ messageID: MessageID) async throws -> MessageDetail {
        let rawDelay = ProcessInfo.processInfo.environment["HIBOSS_DEMO_MESSAGE_DELAY_MS"] ?? "0"
        let delay = UInt64(rawDelay) ?? 0
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        guard let detail = messageDetail(for: messageID) else {
            throw HibossAPIError.requestFailed(status: 404, message: "")
        }
        return detail
    }
}

enum DemoMarkdown {
    static func queue(fallback: [HistoryMessage]) -> [HistoryMessage] {
        guard ProcessInfo.processInfo.environment["HIBOSS_DEMO_MARKDOWN"] == "1" else { return fallback }
        let title = ProcessInfo.processInfo.environment["HIBOSS_DEMO_LONG_TITLE"] == "1"
            ? String(repeating: "Historical title ", count: 12) : "House update"
        return [HistoryMessage(
            id: "markdown-report", body: title, agentName: "codex", direction: "agent_to_boss",
            status: "delivered", priority: "normal", mode: "async", type: "task_update",
            metadata: MessageMetadata(options: [], content: """
            ## Result

            **Complete** report with [evidence](https://example.com).

            - First item
            - Second item

            > Verified details

            ```swift
            let ready = true
            ```
            """),
            createdAt: Date().ISO8601Format(), sessionId: "sess-markdown",
            sessionLabel: "house", sessionBranch: "fix/report", sessionStatus: "working"
        )]
    }
}
