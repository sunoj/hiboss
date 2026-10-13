// Separates session labels from stable nickname suffixes and shortens agent display names.
// Exports: SidebarSessionText; full names remain available for help and accessibility.
// Dependencies: HibossKit session facts and the app's existing Direct localization.

import HibossKit

struct SidebarSessionText {
    let label: String
    let nickname: String?
    let agent: String?
    let fullDescription: String

    init(session: TodaySession, facts: ProjectSession?) {
        let direct = session.id == SessionGrouping.directSessionID
        let explicit = facts?.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        label = direct ? L("Direct") : explicit.flatMap { $0.isEmpty ? nil : $0 }
            ?? facts?.displayLabel ?? session.projectLabel
        let suffix = facts?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        nickname = direct || suffix.isEmpty ? nil : " · " + suffix
        agent = session.agentName.map { $0.components(separatedBy: "@").first ?? $0 }
        fullDescription = [facts?.namedLabel ?? label + (nickname ?? ""), session.agentName]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
