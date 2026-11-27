// The Watching destination: every live panel, with the opened panel's detail beside the wall.
// Exports: WatchingView.
// Dependencies: SwiftUI, HibossKit PanelsModel, DashboardPanelsSection, DashboardPanelDetail.

import HibossKit
import SwiftUI

struct WatchingView: View {
    @ObservedObject var panels: PanelsModel
    var isPreview = false

    var body: some View {
        GeometryReader { geometry in
            if let tile = panels.selectedTile {
                if geometry.size.width >= 760 {
                    HSplitView {
                        wall.frame(minWidth: 360, maxWidth: .infinity)
                        detail(tile).frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
                    }
                } else {
                    detail(tile)
                }
            } else {
                wall
            }
        }
        .background(TodayStyle.ground)
        .task { if !isPreview { await panels.loadIfNeeded() } }
        .accessibilityIdentifier("watching.workspace")
    }

    private var wall: some View {
        ScrollView {
            DashboardPanelsSection(model: panels)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detail(_ tile: PanelTile) -> some View {
        ScrollView { DashboardPanelDetail(tile: tile, model: panels).padding(20) }
            .background(TodayStyle.surface)
            .accessibilityIdentifier("watching.detail")
    }
}
