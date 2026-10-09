// Native Box row showing reference content, metadata and explicit agent provenance.
// Exports: BoxBrowserRow and localized BoxItem presentation helpers.
// Dependencies: SwiftUI, HibossKit and authenticated BoxBrowserMedia thumbnails.

import HibossKit
import SwiftUI

struct BoxBrowserRow: View {
    let item: BoxItem
    @ObservedObject var media: BoxBrowserMedia

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(item.kindTitle, systemImage: item.kindSymbol)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let date = ISODate.parse(item.createdAt) {
                        Text(date, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: item.createdAt).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(verbatim: item.text ?? item.url ?? item.kindTitle).font(.body).lineLimit(3)
                    .textSelection(.enabled)
                if let url = item.url, item.text != nil {
                    Text(verbatim: url).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                if let note = item.note, !note.isEmpty {
                    Text(verbatim: note).font(.callout).lineLimit(2).textSelection(.enabled)
                }
                HStack {
                    if let project = item.project { Label(project, systemImage: "folder") }
                    if !item.tags.isEmpty { Text(verbatim: item.tags.joined(separator: ", ")) }
                }.font(.caption).foregroundStyle(.secondary)
                if let provenance = item.provenance {
                    Label(provenance, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("box.provenance")
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("box.item.\(item.id)")
    }

    @ViewBuilder private var thumbnail: some View {
        if item.hasImageMedia {
            Group {
                if let image = media.thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFit()
                } else if media.errors[item.id] != nil {
                    Button { Task { _ = await media.load(item) } } label: {
                        Label(L("Retry image"), systemImage: "arrow.clockwise")
                    }.help(media.errors[item.id] ?? "")
                } else { ProgressView().controlSize(.small) }
            }
            .frame(width: 80, height: 64)
            .task(id: item.id) { _ = await media.load(item) }
        }
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
        case .link: "link"
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "video"
        case .file: "doc"
        }
    }
}
