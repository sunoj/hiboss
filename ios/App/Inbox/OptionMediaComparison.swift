// Shows option media in an ordered two-up comparison with full-screen zoom.
// Exports: OptionMediaComparison used by pending and resolved decision surfaces.
// Dependencies: SwiftUI, HibossKit OptionMedia, DecisionSettlement and semantic theme colours.

import HibossKit
import SwiftUI

struct OptionMediaComparison: View {
    let options: [String]
    let media: [OptionMedia]
    var settlement: DecisionSettlement? = nil
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
                    OptionMediaTile(media: media, settlement: selection(for: media)) { selectedMedia = media }
                }
            }
            .frame(maxWidth: .infinity)
            .fullScreenCover(item: $selectedMedia) { media in
                OptionMediaZoom(media: media)
            }
        }
    }

    private func selection(for media: OptionMedia) -> DecisionSettlement? {
        guard let settlement,
              media.label.trimmingCharacters(in: .whitespacesAndNewlines)
                == settlement.answer.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return settlement
    }
}

private struct OptionMediaTile: View {
    let media: OptionMedia
    let settlement: DecisionSettlement?
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: media.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                // A flexible surface owns the aspect ratio; the loaded image stays
                // in its overlay so its intrinsic width cannot expand the card.
                Rectangle().fill(Theme.surface2)
                    .aspectRatio(1.35, contentMode: .fit)
                    .overlay {
                        Button(action: open) { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open image for \(media.label)")
                            .accessibilityValue(Text(verbatim: selectionValue))
                    }
                    .overlay {
                        thumbnail
                    }
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(minWidth: 44, minHeight: 44)
            if let settlement {
                Label { Text(verbatim: selectionValue) } icon: { Image(systemName: settlement.symbol) }
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let caption = media.caption, !caption.isEmpty {
                Text(verbatim: caption)
                    .font(.caption)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionValue: String {
        guard let settlement else { return "" }
        return settlement.isAutoDefault ? String(localized: "Auto-selected") : String(localized: "Selected")
    }

    private var thumbnail: some View {
        RemoteImage(url: URL(string: media.url), compact: true,
                    retryIdentifier: "option-media-retry-\(media.label)") { image in
                image.resizable().scaledToFill()
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("option-media-image-\(media.label)")
        }
    }
}

private struct OptionMediaZoom: View {
    let media: OptionMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.mediaBackground.ignoresSafeArea()
            RemoteImage(url: URL(string: media.url)) { image in
                    image.resizable().scaledToFit()
                        .accessibilityIdentifier("option-media-zoom-image")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("Done") { dismiss() }
                .prominentAction()
                .padding()
        }
    }
}
