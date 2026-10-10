// Populated session and Box fixtures for hosted v4 sidebar destination snapshots.
// Exports: PhaseBSnapshotFixtures with real loopback attachments and session inventory.
// Dependencies: HibossKit, BoxBrowserFixtures, and HistorySnapshotMediaServer.

import Foundation
import HibossKit
@testable import HibossIsland

enum PhaseBSnapshotFixtures {
    static func history(baseURL: String) -> [HistoryMessage] {
        let now = Date.now
        return [
            HistoryMessage(id: "open", body: "Ship this navigation?", agentName: "Design Agent",
                direction: "agent_to_boss", status: "delivered", priority: "high",
                metadata: MessageMetadata(options: ["Ship", "Hold"], defaultOption: "Hold",
                    content: "The preview keeps the main action visible.", fileURL: baseURL + "/ship.png"),
                expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(600)),
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-10)),
                sessionId: "hiboss", sessionLabel: "HiBoss", sessionBranch: "ui-v4",
                sessionStatus: "waiting"),
            HistoryMessage(id: "resolved", body: "Keep the native sidebar?", agentName: "Design Agent",
                direction: "agent_to_boss", status: "replied", priority: "normal",
                metadata: MessageMetadata(options: ["Keep", "Replace"]),
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-100)),
                sessionId: "hiboss", sessionLabel: "HiBoss", sessionBranch: "ui-v4"),
            HistoryMessage(id: "answer", body: "Keep", agentName: "Design Agent", direction: "boss_to_agent",
                status: "sent", priority: "normal", replyTo: "resolved",
                metadata: MessageMetadata(options: [], source: "ios"),
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-90)), targetSessionId: "hiboss")
        ]
    }

    static var inventory: [ProjectSession] {
        let now = Date.now
        return [
            ProjectSession(id: "hiboss", projectId: "project", projectSlug: "HiBoss", branch: "ui-v4",
                host: "Mac mini", agentName: "Design Agent", status: "waiting",
                statusText: "Waiting for the navigation review",
                startedAt: AttentionTestSupport.iso(now.addingTimeInterval(-3600)),
                lastSeenAt: AttentionTestSupport.iso(now.addingTimeInterval(-9)), nickname: "otter"),
            ProjectSession(id: "peer", projectId: "project", projectSlug: "HiBoss", branch: "tests",
                host: "Build Mac", agentName: "Test Agent", status: "working",
                lastSeenAt: AttentionTestSupport.iso(now.addingTimeInterval(-120)), nickname: "fox")
        ]
    }
}
