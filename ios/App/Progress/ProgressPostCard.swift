// One progress post as a full-width timeline row: avatar, identity, body, media, like.
// Exports: ProgressPostCard.
// Dependencies: SwiftUI, HibossKit ProgressPost, ProgressMediaView, RelativeTime,
//   ProgressAttributionChip.

import HibossKit
import SwiftUI
import UIKit

struct ProgressPostCard: View {
    let post: ProgressPost
    var onOpenMedia: (ProgressMedia) -> Void
    var onToggleLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressTeamAvatar(urlString: post.team.avatarUrl)
            VStack(alignment: .leading, spacing: 6) {
                header
                Text(post.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !post.media.isEmpty {
                    ProgressMediaView(items: post.media, onOpen: onOpenMedia)
                }
                if !post.tags.isEmpty {
                    Text(post.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressLikeButton(
                    liked: post.liked,
                    count: post.likeCount,
                    action: onToggleLike
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(post.team.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Text("@\(post.team.handle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
                if !post.relativeCreatedAt.isEmpty {
                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text(post.relativeCreatedAt)
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
                if count > 0 {
                    Text("\(count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline)
            .foregroundStyle(liked ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: liked)
        .animation(.snappy, value: count)
        .accessibilityLabel(liked ? String(localized: "Unlike") : String(localized: "Like"))
        .accessibilityValue(String(localized: "\(count) likes"))
    }
}
