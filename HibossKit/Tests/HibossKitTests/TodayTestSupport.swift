// Deterministic message fixtures for Today snapshot and session directory tests.
// Exports: TodayTestSupport with a fixed evaluation time and configurable messages.
// Dependencies: Foundation and the public HibossKit message API.

import Foundation
import HibossKit

enum TodayTestSupport {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static func message(
        _ id: String, session: String? = "session", targetSession: String? = nil,
        age: TimeInterval = 60, createdAt: String? = nil, options: [String] = [],
        mode: String? = "async", status: String = "delivered", sessionStatus: String? = "idle",
        direction: String = "agent_to_boss", priority: String = "normal",
        label: String? = "Project", branch: String? = "main", agent: String? = "Agent",
        expiresIn: TimeInterval? = nil, defaultOption: String? = nil, expired: Bool = false
    ) -> HistoryMessage {
        HistoryMessage(
            id: MessageID(rawValue: id), body: "Body \(id)", agentName: agent,
            direction: direction, status: status, priority: priority, mode: mode,
            metadata: MessageMetadata(options: options, isExpired: expired, defaultOption: defaultOption),
            expiresAt: expiresIn.map { now.addingTimeInterval($0).ISO8601Format() },
            createdAt: createdAt ?? now.addingTimeInterval(-age).ISO8601Format(),
            sessionId: session, targetSessionId: targetSession, sessionLabel: label,
            sessionBranch: branch, sessionStatus: sessionStatus
        )
    }

    static func snapshot(
        _ history: [HistoryMessage], requiredInputs: [HistoryMessage] = [],
        withdrawn: Set<MessageID> = [], health: TodayHealth = .live(checkedAt: now),
        coverageComplete: Bool = true, now: Date = now
    ) -> TodaySnapshot {
        TodaySnapshot(
            history: history, requiredInputs: requiredInputs, withdrawn: withdrawn,
            health: health, coverageComplete: coverageComplete, now: now
        )
    }
}
