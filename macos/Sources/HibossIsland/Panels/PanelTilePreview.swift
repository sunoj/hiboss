// Scaled, display-only panel preview used by wall tiles.
// Exports: PanelTilePreview.
// Dependencies: SwiftUI, PanelRenderer, PanelTile, and PanelWebModel.

import SwiftUI

private struct PanelPreviewSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct PanelTilePreview: View {
    let tile: PanelTile
    @StateObject private var webModel = PanelWebModel()
    @State private var contentSize = CGSize.zero

    private let viewportHeight: CGFloat = 70
    private let minimumScale: CGFloat = 0.62

    var body: some View {
        GeometryReader { proxy in
            let fitScale = scaleToFit(contentSize, in: proxy.size)
            let scale = max(minimumScale, fitScale)
            ZStack(alignment: .bottomLeading) {
                PanelRenderer(spec: tile.fixture.spec, store: tile.store, webModel: webModel, mode: .preview)
                    .render(tile.fixture.spec.root)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(contentMeasurement)
                    .scaleEffect(scale, anchor: .topLeading)
                if fitScale < minimumScale {
                    moreOverlay
                }
            }
            .frame(width: proxy.size.width, height: viewportHeight, alignment: .topLeading)
            .clipped()
        }
        .frame(height: viewportHeight)
        .allowsHitTesting(false)
        .onPreferenceChange(PanelPreviewSizeKey.self) { contentSize = $0 }
    }

    private func scaleToFit(_ size: CGSize, in available: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(1, min(available.width / size.width, available.height / size.height))
    }

    private var contentMeasurement: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: PanelPreviewSizeKey.self, value: proxy.size)
        }
    }

    private var moreOverlay: some View {
        LinearGradient(
            colors: [.clear, Color(nsColor: .controlBackgroundColor).opacity(0.96)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 28)
        .overlay(alignment: .bottomLeading) {
            Label("More in Open panel", systemImage: "ellipsis")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        }
    }
}
