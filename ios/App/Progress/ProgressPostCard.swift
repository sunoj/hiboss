// One inset progress card with project identity, attribution, body, media and a caption footer.
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
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            Text(MessageMarkdown.plainLinks(post.body))
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !post.media.isEmpty {
                ProgressMediaView(items: post.media, onOpen: onOpenMedia)
            }
            HStack(spacing: Space.xs) {
                if !post.tags.isEmpty {
                    tagChips
                } else {
                    Spacer(minLength: 0)
                }
                ProgressLikeButton(
                    liked: post.liked,
                    count: post.likeCount,
                    isSending: isLiking,
                    action: onToggleLike
                )
            }
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
        .hbCard()
        .accessibilityElement(children: .contain)
    }

    @Environment(\.openConnectionSettings) private var openSettings

    private var header: some View {
        HStack(spacing: Space.s) {
            ProjectAvatarView(project: post.projectIdentity, size: AvatarSize.row)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    projectName.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    byline.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    projectName
                    byline
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var projectName: some View {
        Text(verbatim: post.projectIdentity.displayName.isEmpty
             ? post.projectIdentity.slug : post.projectIdentity.displayName)
            .font(.headline)
            .foregroundStyle(Theme.ink)
    }

    private var byline: some View {
        let agent = post.agentLabel ?? (post.agentName.isEmpty ? nil : post.agentName)
        return HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            ProgressAttributionChip(agentLabel: agent, model: post.model, compact: true)
            if let date = post.createdDate {
                if agent != nil || post.model != nil {
                    Text(verbatim: "·").accessibilityHidden(true)
                }
                Text(date, format: .dateTime.hour().minute())
                    .fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.ink2)
    }

    private var tagChips: some View {
        DecisionOptionFlow(layoutDirection: layoutDirection) {
            ForEach(Array(post.tags.enumerated()), id: \.offset) { _, tag in
                Text(verbatim: "#\(tag)")
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, Space.xs)
                    .padding(.vertical, Space.xxs)
                    .background(Theme.surface2, in: Capsule())
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
            HStack(spacing: Space.xxs) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: liked)
                if isSending { DelayedProgressView() }
                if count > 0 {
                    Text(count, format: .number)
                        .font(.caption)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .font(.caption)
            .foregroundStyle(liked ? Theme.negative : Theme.ink2)
            .frame(minWidth: ControlMetric.minTap, minHeight: ControlMetric.minTap)
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .animation(.snappy, value: liked)
        .animation(.snappy, value: count)
        .accessibilityLabel(liked ? String(localized: "Unlike") : String(localized: "Like"))
        .accessibilityValue(String(localized: "\(count) likes"))
    }
}
