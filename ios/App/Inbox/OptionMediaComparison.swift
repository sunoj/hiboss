// Shows option media in an ordered two-up comparison with full-screen zoom.
// Exports: OptionMediaComparison used by pending decision surfaces.
// Dependencies: SwiftUI, HibossKit OptionMedia, and iOS semantic theme colours.

import HibossKit
import SwiftUI

struct OptionMediaComparison: View {
    let options: [String]
    let media: [OptionMedia]
    @State private var selectedMedia: OptionMedia?

    private var orderedMedia: [OptionMedia] {
        options.compactMap { option in
            let normalizedOption = option.trimmingCharacters(in: .whitespacesAndNewlines)
            return media.first {
                $0.label.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedOption
            }
        }
    }

    @ViewBuilder
    var body: some View {
        if !orderedMedia.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                ForEach(orderedMedia) { media in
                    OptionMediaTile(media: media) { selectedMedia = media }
                }
            }
            .frame(maxWidth: .infinity)
            .fullScreenCover(item: $selectedMedia) { media in
                OptionMediaZoom(media: media)
            }
        }
    }
}

private struct OptionMediaTile: View {
    let media: OptionMedia
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(media.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Button(action: open) {
                AsyncImage(url: URL(string: media.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(systemImage: "photo.badge.exclamationmark")
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        placeholder(systemImage: "photo")
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1.35, contentMode: .fit)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open image for (media.label)")
            if let caption = media.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OptionMediaZoom: View {
    let media: OptionMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: URL(string: media.url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.white)
                case .empty:
                    ProgressView().tint(.white)
                @unknown default:
                    ContentUnavailableView("Image unavailable", systemImage: "photo")
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }
}
