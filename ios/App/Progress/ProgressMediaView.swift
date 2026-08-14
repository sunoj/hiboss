// Twitter-style media mosaic for a progress post: one clipped shape, 2 pt gaps.
// Exports: ProgressMediaView, ProgressImageCell.
// Dependencies: SwiftUI, UIKit, HibossKit ProgressMedia, ProgressVideoCell.

import HibossKit
import SwiftUI
import UIKit

struct ProgressMediaView: View {
    let items: [ProgressMedia]
    var onOpen: (ProgressMedia) -> Void
    @State private var measuredAspect: CGFloat?

    var body: some View {
        Group {
            switch items.count {
            case 0: EmptyView()
            case 1: single(items[0])
            case 2: pair
            case 3: triple
            default: quad
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressMediaLayout.cornerRadius, style: .continuous))
        .transaction { $0.animation = nil }
    }

    private func single(_ item: ProgressMedia) -> some View {
        framed(
            aspect: ProgressMediaLayout.clampedAspect(
                width: item.width, height: item.height, measured: measuredAspect
            )
        ) {
            tile(item, reportRatio: item.width == nil || item.height == nil)
        }
    }

    private var pair: some View {
        framed(aspect: ProgressMediaLayout.groupAspect) {
            HStack(spacing: ProgressMediaLayout.gap) {
                tile(items[0])
                tile(items[1])
            }
        }
    }

    private var triple: some View {
        framed(aspect: ProgressMediaLayout.groupAspect) {
            HStack(spacing: ProgressMediaLayout.gap) {
                tile(items[0])
                VStack(spacing: ProgressMediaLayout.gap) {
                    tile(items[1])
                    tile(items[2])
                }
            }
        }
    }

    private var quad: some View {
        framed(aspect: ProgressMediaLayout.groupAspect) {
            VStack(spacing: ProgressMediaLayout.gap) {
                HStack(spacing: ProgressMediaLayout.gap) {
                    tile(items[0])
                    tile(items[1])
                }
                HStack(spacing: ProgressMediaLayout.gap) {
                    tile(items[2])
                    tile(items[3])
                }
            }
        }
    }

    private func framed<Content: View>(
        aspect: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Color(.secondarySystemFill)
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .overlay { content() }
            .clipped()
    }

    @ViewBuilder
    private func tile(_ item: ProgressMedia, reportRatio: Bool = false) -> some View {
        Group {
            switch item.kind {
            case .image:
                ProgressImageCell(
                    media: item,
                    onOpen: { onOpen(item) },
                    onRatio: reportRatio ? { measuredAspect = $0 } : nil
                )
            case .video:
                ProgressVideoCell(media: item, onExpand: { onOpen(item) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct ProgressImageCell: View {
    let media: ProgressMedia
    var onOpen: () -> Void
    var onRatio: ((CGFloat) -> Void)?

    @State private var image: UIImage?
    @State private var failed = false
    @State private var showAlt = false

    var body: some View {
        Color(.secondarySystemFill)
            .overlay { imageFill }
            .overlay {
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: onOpen)
            }
            .overlay(alignment: .bottomLeading) { altButton }
            .clipped()
            .task(id: media.url) { await load() }
            .accessibilityLabel(media.alt ?? String(localized: "Image"))
            .accessibilityAddTraits(.isImage)
            .accessibilityHint(String(localized: "Open full screen"))
            .alert(String(localized: "Alternative text"), isPresented: $showAlt) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(media.alt ?? "")
            }
    }

    @ViewBuilder
    private var imageFill: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else if failed {
            Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var altButton: some View {
        if let alt = media.alt, !alt.isEmpty {
            Button { showAlt = true } label: {
                Text("ALT")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel(String(localized: "Show alternative text"))
            .accessibilityValue(alt)
        }
    }

    private func load() async {
        guard let url = URL(string: media.url) else {
            failed = true
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let loaded = UIImage(data: data), loaded.size.height > 0 else {
                failed = true
                return
            }
            if media.width == nil || media.height == nil {
                onRatio?(loaded.size.width / loaded.size.height)
            }
            image = loaded
        } catch {
            failed = true
        }
    }
}
