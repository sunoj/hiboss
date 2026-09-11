// Shared dashboard tile with native activation, attribution, and freshness.
// Exports: PanelDashboardCard for macOS and iOS panel walls.
// Dependencies: SwiftUI, PanelTilePreview, and PanelFreshness.

import SwiftUI

public struct PanelDashboardCard: View {
    let tile: PanelTile
    let freshness: PanelFreshness
    let pendingCount: Int
    let open: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    public init(tile: PanelTile, freshness: PanelFreshness, pendingCount: Int, open: @escaping () -> Void) {
        self.tile = tile
        self.freshness = freshness
        self.pendingCount = pendingCount
        self.open = open
    }

    public var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    Text(tile.fixture.title).font(.headline).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if tile.preference.placement == .pinned { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
                    if tile.lifecycle.taskState.isTerminal, tile.preference.seenTerminalVersion != tile.metadata?.metadataVersion {
                        Circle().fill(.blue).frame(width: 7, height: 7).accessibilityLabel("Unread result")
                    }
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if pendingCount > 0 {
                    Label(kitL("Needs input") + " · \(pendingCount)", systemImage: "text.bubble.fill")
                        .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                }
                PanelTilePreview(tile: tile)
                footer
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.5 : hovering ? 0.2 : 0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tile.fixture.title)
        .accessibilityHint("Open panel details")
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(tile.sourceLabel).lineLimit(1)
                Spacer(minLength: 0)
                freshnessLabel
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(tile.sourceLabel).lineLimit(1)
                freshnessLabel
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private var freshnessLabel: some View {
        Label(freshness.title, systemImage: freshness.symbol)
            .foregroundStyle(freshness.color).fixedSize(horizontal: false, vertical: true)
    }

    private var surface: Color {
#if os(macOS)
        colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.045)
#else
        Color(uiColor: .secondarySystemGroupedBackground)
#endif
    }
}
