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
                    .frame(minHeight: 44)
            } else { details }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session-facts")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            identityRows.font(.caption).foregroundStyle(Theme.ink2)
            if let step = clean(session.statusText) ?? clean(session.status) {
                Text(verbatim: step).font(.caption).foregroundStyle(Theme.live)
                    .fixedSize(horizontal: false, vertical: true)
            }
            timingRows.font(.caption2).foregroundStyle(Theme.ink3)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var identityRows: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) { identity }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { identity }
                VStack(alignment: .leading, spacing: 2) { identity }
            }
        }
    }

    @ViewBuilder private var timingRows: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) { timing }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { timing }
                VStack(alignment: .leading, spacing: 2) { timing }
            }
        }
    }

    @ViewBuilder private var identity: some View {
        if let agent = clean(session.agentName) {
            Text(verbatim: agent).fixedSize(horizontal: false, vertical: true)
        }
        if let host = clean(session.host) {
            Label { Text(verbatim: host) } icon: { Image(systemName: "desktopcomputer") }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var timing: some View {
        if let date = session.inventoryLastSeenDate {
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let age = Duration.seconds(max(0, context.date.timeIntervalSince(date)))
                    .formatted(.units(allowed: [.days, .hours, .minutes, .seconds],
                                      width: .abbreviated, maximumUnitCount: 1))
                Text("Updated \(age)").fixedSize(horizontal: false, vertical: true)
            }.fixedSize(horizontal: false, vertical: true)
        }
        if let date = session.inventoryStartedDate {
            Text("Started \(date.formatted(date: .abbreviated, time: .shortened))")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
