// Sidebar session sections in the server-derived order: Needs you, Working, Idle.
// Exports: SidebarSessionGroup with the search filter applied inside each section.
// Dependencies: HibossKit SessionDirectory and the project session inventory.

import Foundation
import HibossKit

struct SidebarSessionGroup: Identifiable, Equatable {
    enum Kind: String { case needsYou, working, idle }

    let kind: Kind
    let sessions: [TodaySession]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .needsYou: L("Needs you")
        case .working: L("Working")
        case .idle: L("Idle")
        }
    }

    /// Keeps the directory's order and drops sections the query leaves empty.
    static func groups(_ directory: SessionDirectory, query: String,
                       label: (TodaySession) -> String) -> [SidebarSessionGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sections: [(Kind, [TodaySession])] = [
            (.needsYou, directory.needsYou), (.working, directory.working), (.idle, directory.idle),
        ]
        return sections.compactMap { kind, sessions in
            let matching = trimmed.isEmpty ? sessions : sessions.filter {
                matches($0, query: trimmed, label: label($0))
            }
            return matching.isEmpty ? nil : SidebarSessionGroup(kind: kind, sessions: matching)
        }
    }

    private static func matches(_ session: TodaySession, query: String, label: String) -> Bool {
        label.localizedStandardContains(query)
            || (session.agentName?.localizedStandardContains(query) ?? false)
            || (session.branch?.localizedStandardContains(query) ?? false)
    }
}

/// The sidebar renders every session in one `ForEach`, with a header row before each section.
/// A session whose state changes moves within that list instead of crossing a `Section`, so its
/// row and the list selection survive the move.
enum SidebarSessionRow: Identifiable, Equatable {
    case header(SidebarSessionGroup)
    case session(TodaySession)

    var id: String {
        switch self {
        case let .header(group): "header.\(group.id)"
        case let .session(session): "session.\(session.id)"
        }
    }

    static func rows(_ groups: [SidebarSessionGroup]) -> [SidebarSessionRow] {
        groups.flatMap { group in [.header(group)] + group.sessions.map { .session($0) } }
    }
}
