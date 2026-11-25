// Today row building blocks: the one-line identity under a row's content and its avatar.
// Exports TodayRowIdentity (project, nickname, branch, device) and TodayRowAvatar.
// Dependencies: SwiftUI, HibossKit ProjectIdentity, ProjectAvatarView and AgentAvatarView.

import HibossKit
import SwiftUI

/// The identity shown in a Today row's meta line. The project leads; the rest is detail.
/// A branch already in the label, or a default branch, is not repeated. A chosen agent name
/// is kept; a generated `user@host` name is reduced to the device it runs on.
struct TodayRowIdentity: Equatable {
    let project: String
    let detail: [String]

    private static let defaultBranches: Set<String> = ["main", "master"]
    private static let deviceWords = ["Mac", "MacBook", "iMac", "iPhone", "iPad"]

    static func make(
        label: String?, fallback: String, nickname: String?, branch: String?, host: String?, agent: String?
    ) -> TodayRowIdentity {
        var project = clean(label) ?? clean(fallback) ?? fallback
        var showsBranch = clean(branch).map { !defaultBranches.contains($0.lowercased()) } ?? false
        if let branch = clean(branch), project.hasSuffix("/\(branch)") {
            project = String(project.dropLast(branch.count + 1))
            showsBranch = !defaultBranches.contains(branch.lowercased())
        }
        let named = clean(agent).flatMap { $0.contains("@") ? nil : $0 }
        let agentHost = clean(agent).flatMap { name in name.split(separator: "@", maxSplits: 1).dropFirst().first }
        let device = named ?? (clean(host) ?? agentHost.map(String.init)).map(device(from:))
        let detail = [clean(nickname), showsBranch ? clean(branch) : nil, device].compactMap { $0 }
        return TodayRowIdentity(project: project, detail: detail.filter { $0 != project })
    }

    /// `Mings-MacBook-Air.local` reads as `MacBook Air`; other host names keep their words.
    static func device(from host: String) -> String {
        var words = host.replacingOccurrences(of: ".local", with: "")
            .split(whereSeparator: { $0 == "-" || $0 == " " || $0 == "_" }).map(String.init)
        if words.count > 1, let second = words.dropFirst().first,
           deviceWords.contains(where: { second.hasPrefix($0) }) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    var text: String { ([project] + detail).joined(separator: " · ") }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

/// The leading tile of a Today row: the project, with the agent as a small corner badge.
struct TodayRowAvatar: View {
    let project: ProjectIdentity
    let agent: String?
    /// The name avatars are looked up by; nil keeps the initials (an unidentified sender).
    let lookupName: String?

    var body: some View {
        ProjectAvatarView(project: project, size: AvatarSize.row)
            .overlay(alignment: .bottomTrailing) {
                if let agent {
                    AgentAvatarView(name: agent, size: 18, lookupName: lookupName)
                        .padding(2)
                        .background(Theme.surface, in: Circle())
                        .offset(x: 5, y: 5)
                }
            }
            .padding(.trailing, agent == nil ? 0 : 3)
            .accessibilityHidden(true)
    }
}
