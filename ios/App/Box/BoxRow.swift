// Native Box reference row with authenticated thumbnails and semantic kind labels.
// Exports BoxRow, BoxProvenanceBadge and BoxItem presentation helpers.
// Dependencies: SwiftUI, HibossKit, BoxMediaStore and Theme.

import HibossKit
import SwiftUI

struct BoxRow: View {
    let item: BoxItem
    @ObservedObject var media: BoxMediaStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.boxTitle).font(.body).foregroundStyle(Theme.ink).lineLimit(3)
                BoxProvenanceBadge(item: item)
                if let note = item.note, !note.isEmpty {
                    Text(verbatim: note).font(.callout).foregroundStyle(Theme.ink2).lineLimit(2)
                }
                HStack {
                    Text(verbatim: item.kindLabel)
                    if item.kind == .file, let bytes = item.mediaBytes {
                        Text(verbatim: ByteCountFormatter.string(
                            fromByteCount: Int64(bytes), countStyle: .file))
                    }
                    if let date = ISODate.parse(item.createdAt) { Text(date, style: .relative) }
                }
                .font(.caption).foregroundStyle(Theme.ink2)
                if let project = item.project {
                    Text(verbatim: project).font(.caption).foregroundStyle(Theme.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .task(id: item.id) {
            if item.kind == .image || item.kind == .video { await media.load(item) }
        }
    }

    private var thumbnail: some View {
        ZStack {
            Theme.surface2
            if let image = media.resources[item.id]?.thumbnail {
                Image(uiImage: image).resizable().scaledToFill()
            } else if item.hasMedia && (item.kind == .image || item.kind == .video) {
                if media.errors[item.id] != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                        .accessibilityLabel("Media unavailable")
                } else {
                    CompactImageWait(onRetry: { Task { await media.retry(item) } })
                }
            } else {
                Image(systemName: item.symbol).font(.title2).foregroundStyle(Theme.ink2)
            }
        }
        .frame(width: 64, height: 64).clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(media.errors[item.id] == nil)
    }
}

struct BoxProvenanceBadge: View {
    let item: BoxItem

    var body: some View {
        if let label = item.provenanceLabel {
            Label { Text(verbatim: label) } icon: { Image(systemName: "person.crop.circle") }
                .font(.caption)
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

extension BoxItem {
    var provenanceLabel: String? {
        guard case let .agent(_, name) = author else { return nil }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return String(localized: "Added by an agent")
        }
        return String(localized: "Added by \(name)")
    }

    var boxTitle: String {
        if let text, !text.isEmpty { return text }
        return url ?? note ?? kindLabel
    }

    var kindLabel: String {
        switch kind {
        case .link: String(localized: "Link")
        case .text: String(localized: "Text")
        case .image: String(localized: "Image")
        case .video: String(localized: "Video")
        case .file: String(localized: "File")
        }
    }

    var symbol: String {
        switch kind {
        case .link: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "video"
        case .file: "doc"
        }
    }
}
