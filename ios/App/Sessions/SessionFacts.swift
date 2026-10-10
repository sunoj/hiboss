// Session inventory facts and freshness, with absent server fields omitted.
// Exports SessionFactsStore and SessionFactsHeader for threads and decision provenance.
// Dependencies: HibossKit SessionsServing/ProjectSession, SwiftUI, and Theme.

import HibossKit
import SwiftUI

extension ProjectSession {
    var inventoryStartedDate: Date? { startedAt.flatMap(ISOTimestamp.date(from:)) }
    var inventoryLastSeenDate: Date? { lastSeenAt.flatMap(ISOTimestamp.date(from:)) }
}

@MainActor
final class SessionFactsStore: ObservableObject {
    @Published private(set) var sessions: [ProjectSession] = []
    @Published private(set) var session: ProjectSession?
    @Published private(set) var error: String?

    func load(id: String, api: (any SessionsServing)?) async {
        guard let api else { return }
        do {
            let sessions = try await api.projectSessions()
            guard !Task.isCancelled else { return }
            self.sessions = sessions
            session = sessions.first { $0.id == id }
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

struct SessionFactsHeader: View {
    let session: ProjectSession
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                DisclosureGroup("Session facts") { details }
            } else { details }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-facts")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ProjectAvatarView(project: session.avatarProject, size: 40)
                Text(verbatim: session.namedLabel).font(.title2.bold())
            }
            HStack {
                if let agent = clean(session.agentName) {
                    AgentAvatarView(name: agent, size: 20)
                    Text(verbatim: agent)
                }
                if let host = clean(session.host) { Label { Text(verbatim: host) } icon: {
                    Image(systemName: "desktopcomputer")
                } }
            }.font(.footnote).foregroundStyle(Theme.ink2)
            if let step = clean(session.statusText) ?? clean(session.status) {
                VStack(alignment: .leading, spacing: 4) {
                    Label { Text(verbatim: step) } icon: { Image(systemName: "circle.fill") }
                        .font(.subheadline).foregroundStyle(Theme.live)
                    if let date = session.inventoryLastSeenDate {
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            let age = Duration.seconds(max(0, context.date.timeIntervalSince(date)))
                                .formatted(.units(allowed: [.days, .hours, .minutes, .seconds],
                                                  width: .abbreviated, maximumUnitCount: 1))
                            Text("Updated \(age)").font(.caption).foregroundStyle(Theme.ink3)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if let date = session.inventoryStartedDate {
                Text("Started \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(Theme.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
