// iOS identity adapters for message-derived summaries and inventory-backed project labels.
// Exports projectSessions environment, ProjectSession labels and project lookup helpers.
// Dependencies: SwiftUI, HibossKit project/session models.

import HibossKit
import SwiftUI

private struct ProjectSessionsKey: EnvironmentKey {
    static let defaultValue: [ProjectSession] = []
}

extension EnvironmentValues {
    var projectSessions: [ProjectSession] {
        get { self[ProjectSessionsKey.self] }
        set { self[ProjectSessionsKey.self] = newValue }
    }
}

extension ProjectIdentity {
    static func fallback(_ slug: String) -> ProjectIdentity {
        ProjectIdentity(id: slug, slug: slug, displayName: slug)
    }
}

extension ProjectSession {
    var avatarProject: ProjectIdentity {
        projectRef ?? .fallback(projectSlug ?? label ?? String(id.prefix(8)))
    }

    var namedLabel: String {
        let base = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = base.flatMap { $0.isEmpty ? nil : $0 } ?? displayLabel
        guard let nickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
              !nickname.isEmpty else { return title }
        return "\(title) · \(nickname)"
    }
}

extension Array where Element == ProjectSession {
    func project(slug: String) -> ProjectIdentity {
        first { $0.projectRef?.slug == slug || $0.projectSlug == slug }?.avatarProject ?? .fallback(slug)
    }
}

struct ProjectInventoryModifier: ViewModifier {
    let api: (any SessionsServing)?
    let refreshRequested: Bool
    @State private var sessions: [ProjectSession] = []
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.environment(\.projectSessions, sessions)
            .task(id: api != nil) { await refresh() }
            .onChange(of: refreshRequested) { _, requested in
                if requested { Task { await refresh() } }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
    }

    private func refresh() async {
        guard let api else {
            sessions = []
            return
        }
        do {
            let loaded = try await api.projectSessions()
            guard !Task.isCancelled else { return }
            sessions = loaded
        } catch { /* Cached identity remains usable until the next inventory refresh. */ }
    }
}
