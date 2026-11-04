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

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            Text(verbatim: post.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !post.media.isEmpty {
                ProgressMediaView(items: post.media, onOpen: onOpenMedia)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                if !post.tags.isEmpty {
                    Text(verbatim: post.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.xs)
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
        HStack(alignment: .top, spacing: Space.s) {
            ProjectAvatarView(project: post.projectIdentity, size: AvatarSize.row)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: (post.projectIdentity.displayName.isEmpty
                    ? post.projectIdentity.slug : post.projectIdentity.displayName)).font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                        attribution
                        if hasAttribution && post.createdDate != nil { Text(verbatim: "·") }
                        if let date = post.createdDate { RecordedTimeText(date: date) }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        attribution
                        if let date = post.createdDate { RecordedTimeText(date: date) }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var hasAttribution: Bool { post.agentLabel != nil || post.model != nil }

    @ViewBuilder
    private var attribution: some View {
        if hasAttribution {
            ProgressAttributionChip(agentLabel: post.agentLabel, model: post.model)
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
