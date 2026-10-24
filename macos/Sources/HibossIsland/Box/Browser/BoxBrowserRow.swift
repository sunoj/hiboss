// Native Box row showing reference content, metadata and explicit agent provenance.
// Exports: BoxBrowserRow and localized BoxItem presentation helpers.
// Dependencies: SwiftUI, HibossKit and BoxBrowserMedia's bounded row thumbnails.

import HibossKit
import SwiftUI

struct BoxBrowserRow: View {
    let item: BoxItem
    @ObservedObject var media: BoxBrowserMedia
    let onOpenImage: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: item.displayTitle).font(.headline)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .layoutProbe("box.title.\(item.id)")
                    if !item.summary.isEmpty {
                        Text(verbatim: item.summary).font(.callout).lineLimit(1)
                            .foregroundStyle(item.kind == .link ? Color.accentColor : Color.secondary)
                    }
                    Text(verbatim: item.metadata(now: tick.date))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading] + (typeSize.isAccessibilitySize ? 0 : 56)
        }
        .accessibilityIdentifier("box.item.\(item.id)")
        .layoutProbe("box.item.\(item.id)")
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image = media.thumbnail(item.id) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 44, height: 44)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: item.kindSymbol).font(.title3).foregroundStyle(.secondary)
                    if item.kind == .file, !item.fileExtension.isEmpty {
                        Text(verbatim: item.fileExtension).font(.caption2).lineLimit(1)
                    }
                }
            }
            if item.kind == .video {
                VStack {
                    Image(systemName: "play.circle.fill")
                    if let duration = item.durationTitle { Text(verbatim: duration).font(.caption2) }
                }.foregroundStyle(.primary).padding(2).background(.regularMaterial)
            }
        }
        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
        .layoutProbe("box.thumbnail.\(item.id)")
        .onTapGesture(count: 2) { if item.hasImageMedia { onOpenImage() } }
        // Reruns when the memory cache drops a shown image, which then reloads from disk.
        .task(id: "\(item.id)|\(media.thumbnail(item.id) == nil)") { await media.show(item) }
    }

}

extension BoxItem {
    var hasImageMedia: Bool { hasMedia && (kind == .image || mediaType?.hasPrefix("image/") == true) }

    var provenance: String? {
        guard case let .agent(_, name) = author else { return nil }
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? L("Added by an agent") : L("Added by \(cleaned)")
    }

    var kindTitle: String {
        kind.title
    }

    var kindSymbol: String {
        switch kind {
        case .link: "globe"
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "video"
        case .file: "doc"
        }
    }
}
