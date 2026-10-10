// Recent project peers ranked by inventory activity, falling back to message timestamps.
// Exports: SessionPeer and SessionPeers; filtering precedes deduplication and display cap.
// Dependencies: HibossKit inventory, message grouping, and HistoryTimestamp parsing.

import Foundation
import HibossKit

struct SessionPeer: Identifiable {
    let session: ProjectSession
    let lastActivity: Date
    var id: String { session.id }
}

enum SessionPeers {
    static let window: TimeInterval = 24 * 60 * 60
    static let visibleLimit = 5

    static func recent(context: SessionContext, now: Date) -> [SessionPeer] {
        let messages = Dictionary(grouping: context.snapshot.history, by: SessionGrouping.sessionKey(for:))
        let candidates = context.inventory.compactMap { peer -> SessionPeer? in
            guard peer.id != context.id, belongs(peer, to: context) else { return nil }
            let activity = peer.lastSeenAt.flatMap(HistoryTimestamp.date)
                ?? messages[peer.id]?.compactMap { HistoryTimestamp.date(from: $0.createdAt) }.max()
            guard let activity, activity <= now, now.timeIntervalSince(activity) <= window else { return nil }
            return SessionPeer(session: peer, lastActivity: activity)
        }.sorted {
            $0.lastActivity == $1.lastActivity ? $0.id < $1.id : $0.lastActivity > $1.lastActivity
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    static func visible(_ peers: [SessionPeer], showAll: Bool) -> [SessionPeer] {
        showAll ? peers : Array(peers.prefix(visibleLimit))
    }

    private static func belongs(_ peer: ProjectSession, to context: SessionContext) -> Bool {
        if let id = context.facts?.projectId ?? context.facts?.projectRef?.id,
           let peerID = peer.projectId ?? peer.projectRef?.id {
            return peerID == id
        }
        guard let project = context.project else { return false }
        return (peer.projectRef?.slug ?? peer.projectSlug) == project
    }
}
