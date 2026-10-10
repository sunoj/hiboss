// macOS project identity lookup and session names without changing shared models.
// Exports: ProjectSession presentation helpers, projectSessions environment, ProjectLabelView.
// Dependencies: SwiftUI and HibossKit project inventory.

import HibossKit
import SwiftUI

extension ProjectSession {
    var namedLabel: String {
        let base = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = base.flatMap { $0.isEmpty ? nil : $0 } ?? displayLabel
        let suffix = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return suffix.isEmpty ? title : "\(title) · \(suffix)"
    }

    var avatarProject: ProjectIdentity {
        projectRef ?? ProjectIdentity(id: projectId ?? projectSlug ?? id,
            slug: projectSlug ?? displayLabel, displayName: projectSlug ?? displayLabel)
    }
}

private struct ProjectSessionsKey: EnvironmentKey {
    static let defaultValue: [ProjectSession] = []
}

extension EnvironmentValues {
    var projectSessions: [ProjectSession] {
        get { self[ProjectSessionsKey.self] }
        set { self[ProjectSessionsKey.self] = newValue }
    }
}

struct ProjectLabelView: View {
    let slug: String
    @Environment(\.projectSessions) private var sessions

    var body: some View {
        let project = sessions.first { ($0.projectRef?.slug ?? $0.projectSlug) == slug }?.avatarProject
            ?? ProjectIdentity(id: slug, slug: slug, displayName: slug)
        HStack(spacing: 6) {
            ProjectAvatarView(project: project, size: 20)
            Text(verbatim: project.displayName)
        }
    }
}
