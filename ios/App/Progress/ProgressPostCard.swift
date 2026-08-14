// One progress post as a native list row: project, relative time, body, media.
// Exports: ProgressPostCard.
// Dependencies: SwiftUI, HibossKit ProgressPost, ProgressMediaView, RelativeTime.

import HibossKit
import SwiftUI

struct ProgressPostCard: View {
    let post: ProgressPost
    var onOpenMedia: (ProgressMedia) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(post.project)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !post.relativeCreatedAt.isEmpty {
                    Text(post.relativeCreatedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            if !post.agentName.isEmpty {
                Text(post.agentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
