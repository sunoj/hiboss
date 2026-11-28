// Box grid tiles with authenticated thumbnails and localized item metadata.
// Exports BoxTile and BoxThumbnail for the browser and collection covers.
// Dependencies: SwiftUI, HibossKit, BoxMediaStore and Theme.

import HibossKit
import SwiftUI

struct BoxTile: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            preview
                .frame(maxWidth: .infinity)
                .frame(minHeight: AvatarSize.row * 2)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Radius.small))
                .accessibilityHidden(true)
            tileTitle.font(.subheadline.weight(.semibold))
            badge
            if let date = ISOTimestamp.date(from: item.createdAt) {
                RecordedTimeText(date: date) { time in
                    Text(verbatim: [time, item.project].compactMap { $0 }.joined(separator: " · "))
                }
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .lineLimit(textSize.isAccessibilitySize ? nil : 1)
            } else if let project = item.project {
                Text(verbatim: project).font(.caption).foregroundStyle(Theme.ink2)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
    }

    private var title: String {
        item.boxTitle.split(whereSeparator: \.isNewline).first.map(String.init) ?? item.boxTitle
    }

    @ViewBuilder private var tileTitle: some View {
        if textSize.isAccessibilitySize {
            Text(verbatim: title)
        } else {
            Text(verbatim: title).lineLimit(2, reservesSpace: true)
        }
    }

    private var provenance: String {
        guard case let .agent(_, name) = item.author else { return String(localized: "You") }
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return String(localized: "Added by \(name)")
        }
        return String(localized: "Added by an agent")
    }

    private var badge: some View {
        HStack(spacing: Space.xxs) {
            provenanceText
            if item.liked { Image(systemName: "heart.fill").font(.caption) }
        }
        .foregroundStyle(Theme.ink2)
    }

    private var provenanceText: some View {
        Text(verbatim: provenance)
            .font(.caption2.weight(.medium))
            .lineLimit(textSize.isAccessibilitySize ? nil : 1)
            .padding(.horizontal, Space.xxs)
            .padding(.vertical, Space.xxs)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Radius.small))
    }

    private var accessibilitySummary: String {
        [title, item.kindLabel, item.kind == .link ? item.summary : nil, item.sizeLabel,
         provenance, item.liked ? String(localized: "Liked") : nil, item.relativeTime, item.project]
            .compactMap { $0 }.formatted(.list(type: .and))
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .image, .video:
            BoxThumbnail(item: item, media: media).frame(height: AvatarSize.row * 2)
        case .text:
            Text(verbatim: item.text ?? item.note ?? item.kindLabel)
                .font(.caption).foregroundStyle(Theme.ink2)
                .lineLimit(textSize.isAccessibilitySize ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.xs)
        case .link:
            previewLabel(item.summary ?? item.kindLabel)
        case .file:
            let kind = item.fileExtension.isEmpty ? item.formatLabel : item.fileExtension
            previewLabel([kind, item.sizeLabel].compactMap { $0 }.joined(separator: " · "))
        }
    }

    private func previewLabel(_ value: String) -> some View {
        Label {
            Text(verbatim: value).lineLimit(textSize.isAccessibilitySize ? nil : 2)
        } icon: {
            Image(systemName: item.symbol)
        }
        .font(.caption)
        .foregroundStyle(Theme.ink2)
        .padding(Space.xs)
    }
}

struct BoxThumbnail: View {
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Theme.surface2
                if let image = media.thumbnail(item.id) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if item.hasMedia && (item.kind == .image || item.kind == .video) {
                    if media.thumbnailErrors[item.id] != nil {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                            .accessibilityLabel("Media unavailable")
                    } else {
                        CompactImageWait(onRetry: { Task { await media.retryThumbnail(item) } })
                    }
                } else {
                    VStack(spacing: Space.xxs) {
                        Image(systemName: item.symbol).font(.title2)
                        if item.kind == .file {
                            Text(verbatim: item.fileExtension).font(.caption2).lineLimit(1)
                        }
                    }.foregroundStyle(Theme.ink2)
                }
                if item.kind == .video {
                    VStack {
                        Image(systemName: "play.circle.fill").font(.title2)
                        if let duration = item.durationLabel {
                            Text(verbatim: duration).font(.caption)
                        }
                    }.padding(Space.xxs)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.small))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.small))
        }
        .accessibilityHidden(media.thumbnailErrors[item.id] == nil)
        .task(id: "\(item.id)#\(media.thumbnailEpochs[item.id] ?? 0)") { await media.showThumbnail(item) }
    }
}
