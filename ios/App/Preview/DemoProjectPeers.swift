// Offline project identity fixtures for avatar and recent-peer UI coverage.
// Exports DemoProjectPeers; depends on HibossKit and Foundation timestamps.

import Foundation
import HibossKit

enum DemoProjectPeers {
    static func queue(fallback: [HistoryMessage]) -> [HistoryMessage] {
        ProcessInfo.processInfo.environment["HIBOSS_DEMO_PEERS"] == "1" ? messages : fallback
    }

    static var messages: [HistoryMessage] {
        [HistoryMessage(id: "peer-update", body: "Preparing the release", agentName: "worker-deploy",
                        direction: "agent_to_boss", status: "delivered", priority: "normal",
                        createdAt: Date().addingTimeInterval(-60).ISO8601Format(), sessionId: "sess-deploy")]
    }

    static var sessions: [ProjectSession] {
        let project = ProjectIdentity(id: "hiboss", slug: "hiboss", displayName: "HiBoss",
                                      avatarURL: URL(string: "https://127.0.0.1:1/unavailable.png"))
        return (0..<8).map { index in
            ProjectSession(
                id: index == 0 ? "sess-deploy" : "peer-\(index)", projectId: project.id,
                projectSlug: project.slug, branch: "release/v2.4", label: "prod-release",
                projectRef: project, host: "Mac mini", agentName: "worker-\(index)",
                status: "working", statusText: "Preparing the release",
                lastSeenAt: Date().addingTimeInterval(-Double(index + 1) * 60).ISO8601Format(),
                nickname: ["otter", "palm", "coral", "heron", "turtle", "whale", "fern", "mango"][index]
            )
        }
    }
}
