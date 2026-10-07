// One progress post as a full-width timeline row: avatar, identity, body, media, like.
// Exports: ProgressPostCard.
// Dependencies: SwiftUI, HibossKit ProgressPost, ProgressMediaView, RelativeTime,
//   ProgressAttributionChip.

import HibossKit
import SwiftUI
import UIKit

struct ProgressPostCard: View {
    let post: ProgressPost
    var isLiking = false
    var likeError: String? = nil
    var onOpenMedia: (ProgressMedia) -> Void
    var onToggleLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressTeamAvatar(urlString: post.team.avatarUrl)
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(verbatim: post.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !post.media.isEmpty {
                    ProgressMediaView(items: post.media, onOpen: onOpenMedia)
                }
                if !post.tags.isEmpty {
                    Text(verbatim: post.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressLikeButton(
                    liked: post.liked,
                    count: post.likeCount,
                    isSending: isLiking,
                    action: onToggleLike
                )
                if isLiking {
                    PendingStateView(title: String(localized: "Updating like…"),
                                     onSettings: openSettings)
                }
                if let likeError {
                    Label {
                        Text(verbatim: likeError)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                        .font(.hbCaption).foregroundStyle(Theme.warn)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @Environment(\.openConnectionSettings) private var openSettings

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: post.team.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: "·")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Text(verbatim: "@\(post.team.handle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
                if !post.relativeCreatedAt.isEmpty {
                    Text(verbatim: "·")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(verbatim: post.relativeCreatedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if post.agentLabel != nil || post.model != nil {
                ProgressAttributionChip(agentLabel: post.agentLabel, model: post.model)
            }
        }
    }
}

struct ProgressLikeButton: View {
    let liked: Bool
    let count: Int
    var isSending = false
    var action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: liked)
                if isSending { DelayedProgressView() }
                if count > 0 {
                    Text(count, format: .number)
                        .font(.subheadline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline)
            .foregroundStyle(liked ? Theme.negative : Theme.ink2)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .animation(.snappy, value: liked)
        .animation(.snappy, value: count)
        .accessibilityLabel(liked ? String(localized: "Unlike") : String(localized: "Like"))
        .accessibilityValue(String(localized: "\(count) likes"))
    }
}
