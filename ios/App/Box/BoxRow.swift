// Native Box reference row with authenticated, downsampled thumbnails and semantic kind labels.
// Exports BoxRow and BoxThumbnail for list rows, content cards and the photo grid.
// Dependencies: SwiftUI, HibossKit, BoxMediaStore and Theme.

import HibossKit
import SwiftUI

struct BoxRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .body) private var rowHeight = 64
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore

    var grid = false

    private var layout: AnyLayout {
        grid || textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    var body: some View {
        layout {
            if !grid || item.kind != .text {
                BoxThumbnail(item: item, media: media)
                    .frame(width: grid ? nil : 56, height: grid ? (item.hasMedia ? 120 : 44) : 56)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.boxTitle).font(.body).foregroundStyle(Theme.ink)
                    .lineLimit(textSize.isAccessibilitySize ? nil : (grid ? (item.hasMedia ? 2 : 4) : 1))
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = item.summary, !summary.isEmpty {
                    Text(verbatim: summary).font(.callout)
                        .foregroundStyle(item.kind == .link ? Theme.link : Theme.ink2)
                        .lineLimit(textSize.isAccessibilitySize ? nil : (grid ? (item.hasMedia ? 1 : 2) : 1))
                }
                metadata
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(grid ? 12 : 0)
        .frame(maxWidth: .infinity, minHeight: grid ? nil : rowHeight, alignment: .leading)
        .frame(maxHeight: grid ? .infinity : nil, alignment: .topLeading)
        .background(grid ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            grid || textSize.isAccessibilitySize ? 0 : dimensions[.leading] + 68
        }
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if item.liked {
                Image(systemName: "heart.fill").font(.caption)
                    .foregroundStyle(.secondary).accessibilityLabel("Liked")
            }
            if let date = ISOTimestamp.date(from: item.createdAt) {
                RecordedTimeText(date: date) { time in
                    Text(verbatim: [item.kindLabel, item.sizeLabel, time, item.authorLabel, item.project]
                        .compactMap { $0 }.joined(separator: " · "))
                }.font(.caption).foregroundStyle(Theme.ink2)
                    .lineLimit(textSize.isAccessibilitySize ? nil : (grid ? 2 : 1))
            } else {
                Text(verbatim: item.metadata).font(.caption).foregroundStyle(Theme.ink2)
                    .lineLimit(textSize.isAccessibilitySize ? nil : (grid ? 2 : 1))
            }
        }
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
                    VStack(spacing: 2) {
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
                    }.padding(4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityHidden(media.thumbnailErrors[item.id] == nil)
        .task(id: "\(item.id)#\(media.thumbnailEpochs[item.id] ?? 0)") { await media.showThumbnail(item) }
    }
}
