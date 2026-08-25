// Horizontally scrolling project summary cards for the Home tab.
// Exports: HomeProjectCard and HomeProjectStrip.
// Dependencies: SwiftUI, HibossKit HomeProject, Theme tokens.

import HibossKit
import SwiftUI

struct HomeProjectStrip: View {
    let projects: [HomeProject]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects")
                .font(.hbH3)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
            if projects.isEmpty {
                Text("No projects yet")
                    .font(.hbCallout)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(projects) { HomeProjectCard(project: $0) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct HomeProjectCard: View {
    let project: HomeProject

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(project.name)
                .font(.hbBodyStrong)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            sessionCounts
            if project.pendingDecisions > 0 {
                Label("\(project.pendingDecisions) pending", systemImage: "exclamationmark.bubble")
                    .font(.hbCaption)
                    .foregroundStyle(Theme.warn)
            }
            if let post = project.lastPost {
                Text(post.body)
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            } else {
                Text("No recent posts")
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink3)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var sessionCounts: some View {
        let s = project.sessions
        return HStack(spacing: 8) {
            countPill(s.working, label: "working", tint: Theme.positive)
            countPill(s.waiting, label: "waiting", tint: Theme.warn)
            countPill(s.blocked, label: "blocked", tint: Theme.negative)
            countPill(s.idle, label: "idle", tint: Theme.ink3)
        }
        .font(.hbCaption)
    }

    @ViewBuilder
    private func countPill(_ count: Int, label: String, tint: Color) -> some View {
        if count > 0 {
            Text("\(count) \(label)")
                .foregroundStyle(tint)
        }
    }
}
