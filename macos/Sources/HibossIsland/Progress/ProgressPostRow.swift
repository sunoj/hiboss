// Native timeline row showing provenance, post text, media, tags and mutation feedback.
// Exports: ProgressPostRow with like and delete actions supplied by the workspace.
// Dependencies: SwiftUI, HibossKit, project session identity and ProgressMediaGrid.

import HibossKit
import SwiftUI

struct ProgressPostRow: View {
    @Environment(\.projectSessions) private var sessions
    let post: ProgressPost
    let isLiking: Bool
    let isDeleting: Bool
    let error: String?
    let onOpen: (ProgressMedia) -> Void
    let onLike: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(verbatim: post.body).font(.body).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !post.media.isEmpty { ProgressMediaGrid(items: post.media, onOpen: onOpen) }
            if !post.tags.isEmpty {
                Text(verbatim: post.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption).foregroundStyle(TodayStyle.secondary)
            }
            actions
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(TodayStyle.signal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.post.\(post.id)")
    }

    private var header: some View {
        HStack(alignment: .top) {
            ProjectAvatarView(project: project, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: project.displayName).font(.headline)
                Text(verbatim: post.agentLabel ?? (post.agentName.isEmpty ? L("Agent") : post.agentName))
                    .font(.callout).foregroundStyle(TodayStyle.live)
            }
            Spacer()
            if let date = ISODate.parse(post.createdAt) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(verbatim: SharedTimestamp.string(date, now: context.date))
                        .font(.caption).foregroundStyle(TodayStyle.tertiary)
                        .frame(width: 160, alignment: .trailing)
                        .layoutProbe("progress.timestamp.\(post.id)")
                        .help(date.formatted(date: .complete, time: .shortened))
                }
            } else {
                Text(verbatim: post.createdAt).font(.caption).foregroundStyle(TodayStyle.tertiary)
            }
        }
    }

    private var project: ProjectIdentity {
        ProgressProjectIdentity.resolve(post.projectIdentity, sessions: sessions)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(action: onLike) {
                Label {
                    Text(post.likeCount, format: .number)
                } icon: { Image(systemName: post.liked ? "heart.fill" : "heart") }
            }
            .accessibilityLabel(post.liked ? L("Unlike") : L("Like"))
            .accessibilityValue(L("\(post.likeCount) likes"))
            .disabled(isLiking || isDeleting)
            if isLiking { ProgressView().controlSize(.small).accessibilityLabel(L("Updating like…")) }
            Spacer()
            if isDeleting { ProgressView().controlSize(.small).accessibilityLabel(L("Deleting post…")) }
            Button(L("Delete"), systemImage: "trash", role: .destructive, action: onDelete)
                .disabled(isLiking || isDeleting)
        }
        .buttonStyle(.borderless)
    }
}
