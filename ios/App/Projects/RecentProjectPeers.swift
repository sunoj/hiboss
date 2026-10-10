// Recent project peers sorted by inventory activity, with message timestamps as a fallback.
// Exports RecentProjectPeers and dated peer rows; depends on HibossKit and Foundation.

import Foundation
import HibossKit

struct RecentProjectPeer: Identifiable {
    let session: ProjectSession
    let activityDate: Date
    var id: String { session.id }
}

enum RecentProjectPeers {
    static let window: TimeInterval = 24 * 60 * 60
    static let previewLimit = 5

    static func all(current: ProjectSession, sessions: [ProjectSession], messages: [HistoryMessage],
                    now: Date) -> [RecentProjectPeer] {
        let dates = Dictionary(grouping: messages, by: SessionGrouping.sessionKey(for:))
            .mapValues { $0.compactMap(\.createdDate).max() }
        let candidates = sessions.compactMap { session -> RecentProjectPeer? in
            guard session.id != current.id, sameProject(session, current),
                  let date = session.inventoryLastSeenDate ?? dates[session.id] ?? nil,
                  date <= now, now.timeIntervalSince(date) <= window else { return nil }
            return RecentProjectPeer(session: session, activityDate: date)
        }.sorted {
            $0.activityDate == $1.activityDate ? $0.id < $1.id : $0.activityDate > $1.activityDate
        }
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.id).inserted }
    }

    static func preview(_ peers: [RecentProjectPeer]) -> [RecentProjectPeer] {
        Array(peers.prefix(previewLimit))
    }

    private static func sameProject(_ lhs: ProjectSession, _ rhs: ProjectSession) -> Bool {
        if let left = lhs.projectRef?.id ?? lhs.projectId,
           let right = rhs.projectRef?.id ?? rhs.projectId { return left == right }
        guard let left = lhs.projectRef?.slug ?? lhs.projectSlug,
              let right = rhs.projectRef?.slug ?? rhs.projectSlug else { return false }
        return left == right
    }
}
