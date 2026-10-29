// Adapts streamed messages and connection evidence to the shared Today projection.
// Exports: TodayProjection; ordering and session classification belong to HibossKit.
// Dependencies: Foundation, HibossKit TodaySnapshot and OptionFlowStore.

import Foundation
import HibossKit

enum TodayProjection {
    static func merge(history: [HistoryMessage], live: OptionMessage?,
                      requiredInputs: [HistoryMessage] = []) -> [HistoryMessage] {
        var messages = history
        if let live, !messages.contains(where: { $0.id == live.id }) {
            messages.append(historyMessage(from: live))
        }
        guard !requiredInputs.isEmpty else { return messages }
        var indices: [MessageID: Int] = [:]
        indices.reserveCapacity(messages.count + requiredInputs.count)
        for (index, message) in messages.enumerated() where indices[message.id] == nil {
            indices[message.id] = index
        }
        for message in requiredInputs {
            if let index = indices[message.id] {
                messages[index] = message
            } else {
                indices[message.id] = messages.count
                messages.append(message)
            }
        }
        return messages
    }

    static func historyMessage(from live: OptionMessage) -> HistoryMessage {
        HistoryMessage(id: live.id, body: live.body, agentName: live.agentName,
            direction: "agent_to_boss", status: "delivered", priority: "",
            metadata: live.metadata, expiresAt: live.expiresAt, createdAt: "",
            sessionLabel: live.sessionLabel, sessionBranch: live.sessionBranch)
    }

    static func health(connection: ConnectionState, history: HistoryState, checkedAt: Date,
                       loadedAt: Date? = nil) -> TodayHealth {
        if (history == .loading || history == .idle) && loadedAt == nil { return .loading }
        if case .failed = history { return .offline(since: loadedAt ?? checkedAt) }
        switch connection {
        case .connected: return .live(checkedAt: loadedAt ?? checkedAt)
        case .connecting: return .connecting
        case .disconnected, .failed: return .offline(since: checkedAt)
        }
    }
}
