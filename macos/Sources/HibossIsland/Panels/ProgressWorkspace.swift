// Progress destination wrapping existing panel controls in the native v4 shell.
// Exports: ProgressWorkspace; rendering preserves null series samples and questionnaires.
// Dependencies: SwiftUI, HibossKit PanelsModel, and DashboardPanelDetail.

import HibossKit
import SwiftUI

struct ProgressWorkspace: View {
    @ObservedObject var model: PanelsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let tile = model.selectedTile {
                    DashboardPanelDetail(tile: tile, model: model)
                } else {
                    Text(L("Progress")).font(.title2.bold())
                    DashboardPanelsSection(model: model)
                }
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .workspaceChrome()
        .background(TodayStyle.ground).tint(TodayStyle.live)
        .task { await model.loadIfNeeded() }
        .accessibilityIdentifier("progress.workspace")
    }
}
