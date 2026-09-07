// Minimal native shell for choosing and measuring the two untouched fixtures.
// Exports: PanelWebSpikeApp and the SwiftUI scene.
// Dependencies: SwiftUI, HostModel, and WebPanelView.

import SwiftUI

@main
struct PanelWebSpikeApp: App {
    @StateObject private var model = HostModel()

    var body: some Scene {
        WindowGroup("Panel Web Spike") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Fixture", selection: Binding(get: { model.fixtureName }, set: { model.selectFixture($0) })) {
                        Text("Metric panel").tag("metric-panel")
                        Text("Rollout decision").tag("rollout-decision")
                    }
                    Button("Remount") { model.mountRevision += 1 }
                    Button("Run 200 applies") { model.runApplyProbe() }
                }
                Text("Natural content height: \(Int(model.contentHeight)) pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                WebPanelView(model: model)
                    .frame(minHeight: 180, idealHeight: model.contentHeight, maxHeight: 2000)
                Text(model.logLines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
            .frame(minWidth: 520, idealWidth: 520, maxWidth: 520, minHeight: 360)
        }
    }
}
