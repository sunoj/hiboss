// Provides the HiBoss main window, which hosts the message history.
// Exports: MainView for the native window scene.
// Dependencies: SwiftUI, AppSettings, OptionFlowStore, and HistoryView.

import SwiftUI
import HibossKit

struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore

    var body: some View {
        HistoryView(flow: flow)
            .frame(minWidth: 760, minHeight: 520)
    }
}
