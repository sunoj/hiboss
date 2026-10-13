// Resolves progress provenance against the same project inventory used by the sidebar.
// Exports: ProgressProjectIdentity with case-insensitive slug and display-name matching.
// Dependencies: HibossKit and the macOS ProjectSession avatar presentation helper.

import HibossKit

enum ProgressProjectIdentity {
    static func resolve(_ fallback: ProjectIdentity, sessions: [ProjectSession]) -> ProjectIdentity {
        let names = [fallback.slug, fallback.displayName]
        let matches = sessions.filter { session in
            let project = session.avatarProject
            return project.id == fallback.id || [project.slug, project.displayName].contains { name in
                names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
        }.map(\.avatarProject)
        return matches.first { $0.avatarURL != nil }
            ?? (fallback.avatarURL != nil ? fallback : matches.first ?? fallback)
    }
}
