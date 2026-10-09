// Session facts and reply targets derived without changing shared decision ordering.
// Exports: SessionContext for the thread header, composer, and project inspector.
// Dependencies: HibossKit TodaySnapshot, ProjectSession, and HistoryTimestamp.

import Foundation
import HibossKit

struct SessionContext {
    let id: String
    let snapshot: OverviewSnapshot
    let inventory: [ProjectSession]

    var facts: ProjectSession? { inventory.first { $0.id == id } }
    var summary: TodaySession? {
        let directory = snapshot.today.sessionDirectory
        return (directory.needsYou + directory.working + directory.idle).first { $0.id == id }
    }
    var project: String? { facts?.projectRef?.slug ?? facts?.projectSlug }
    var title: String { project ?? summary?.projectLabel ?? L("Session") }
    var branch: String? { facts?.branch ?? summary?.branch }
    var decisions: [AttentionItem] {
        snapshot.today.decisions.filter { SessionGrouping.sessionKey(for: $0.message) == id }
    }
    var newestAgentMessage: HistoryMessage? {
        replyTargets.max {
            (HistoryTimestamp.date(from: $0.createdAt) ?? .distantPast)
                < (HistoryTimestamp.date(from: $1.createdAt) ?? .distantPast)
        }
    }
    var replyTargets: [HistoryMessage] {
        let openIDs = Set(decisions.map(\.id))
        return snapshot.messages(for: .session(id)).filter { message in
            guard message.direction == "agent_to_boss" else { return false }
            let isDecision = !message.options.isEmpty || message.defaultOption != nil
                || message.mode == "blocking"
            return !isDecision || openIDs.contains(message.id)
        }
    }
    func replyTargetLabel(for message: HistoryMessage) -> String {
        if decisions.contains(where: { $0.id == message.id }) {
            return L("Custom answer to: \(message.body)")
        }
        let firstLine = message.body.components(separatedBy: .newlines).first ?? message.body
        return L("Replying to: \(firstLine)")
    }
    var peers: [ProjectSession] {
        inventory.filter { peer in
            guard peer.id != id else { return false }
            if let projectID = facts?.projectId { return peer.projectId == projectID }
            guard let project else { return false }
            return (peer.projectRef?.slug ?? peer.projectSlug) == project
        }
    }
}
