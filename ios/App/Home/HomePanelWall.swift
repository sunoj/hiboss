// iOS panel tile wall added below the Home attention surface.
// Exports: HomePanelWall.
// Dependencies: SwiftUI, HibossKit PanelsModel, PanelTilePreview, and semantic styles.

import HibossKit
import SwiftUI

struct HomePanelWall: View {
    @ObservedObject var model: PanelsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuredWidth: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Live panels").font(.title3.bold())
                Spacer()
                if model.isDemoMode { Text("Demo").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            if model.isDemoMode {
                Text("Fixture panels rendered locally — no server connection.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.tiles.isEmpty {
                ProgressView("Loading panels…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                wall
            }
        }
        .padding(.horizontal, 16)
        .task { await model.loadIfNeeded() }
    }

    private var wall: some View {
        GeometryReader { proxy in
            let positions = model.positions(for: proxy.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(model.tiles) { tile in
                    if let position = positions.first(where: { $0.id == tile.id }) {
                        HomePanelTile(tile: tile, model: model, reduceMotion: reduceMotion)
                            .frame(width: position.frame.width, height: position.frame.height)
                            .offset(x: position.frame.minX, y: position.frame.minY)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { measuredWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { measuredWidth = $0 }
        }
        .frame(height: model.wallHeight(of: model.positions(for: measuredWidth)))
    }
}

private struct HomePanelTile: View {
    let tile: PanelTile
    @ObservedObject var model: PanelsModel
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(tile.fixture.title).font(.headline).lineLimit(1)
                Spacer(minLength: 4)
                Label(model.freshness(for: tile).title, systemImage: model.freshness(for: tile).symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(model.freshness(for: tile).color)
                    .fixedSize()
            }
            Text(tile.sourceLabel).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            PanelTilePreview(tile: tile)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
        .scaleEffect(pulse ? 1.012 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.fixture.title), \(tile.sourceLabel), \(model.freshness(for: tile).title)")
        .onChange(of: tile.store.state) { _, _ in
            guard !reduceMotion else { return }
            pulse = true
            withAnimation(.easeOut(duration: 0.28).delay(model.animationDelay(for: tile))) { pulse = false }
        }
    }
}
