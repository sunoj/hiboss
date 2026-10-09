// Adapts streamed messages and connection evidence to the shared Today projection.
// Exports: TodayProjection; ordering and session classification belong to HibossKit.
// Dependencies: Foundation, HibossKit TodaySnapshot and OptionFlowStore.

import Foundation
import HibossKit

enum TodayProjection {
    static func merge(history: [HistoryMessage], live: OptionMessage?) -> [HistoryMessage] {
        guard let live, !history.contains(where: { $0.id == live.id }) else { return history }
        return history + [historyMessage(from: live)]
    }

    static func historyMessage(from live: OptionMessage) -> HistoryMessage {
        HistoryMessage(id: live.id, body: live.body, agentName: live.agentName,
            direction: "agent_to_boss", status: "delivered", priority: "",
            metadata: live.metadata, expiresAt: live.expiresAt, createdAt: "",
            sessionLabel: live.sessionLabel, sessionBranch: live.sessionBranch)
    }

    static func decisions(history: [HistoryMessage], live: OptionMessage? = nil, now: Date,
                          withdrawn: Set<MessageID> = []) -> [AttentionItem] {
        AttentionModel.items(from: merge(history: history, live: live).filter { !withdrawn.contains($0.id) },
            now: now)
    }

    static func withdrawn(feedback: [MessageID: ReplyFeedback]) -> Set<MessageID> {
        Set(feedback.compactMap { id, outcome in outcome == .alreadyResolved ? id : nil })
    }

    static func health(connection: ConnectionState, history: HistoryState, checkedAt: Date) -> TodayHealth {
        if history == .loading || history == .idle { return .loading }
        switch connection {
        case .connected: return .live(checkedAt: checkedAt)
        case .connecting: return .connecting
        case .disconnected, .failed: return .offline(since: checkedAt)
        }
    }

    /// A full history page may hide older open decisions; it cannot establish coverage.
    static func coverage(history: [HistoryMessage], state: HistoryState) -> Bool {
        state == .loaded && history.count < AppConstants.API.historyLimit
    }
}
