// Fixture-driven Panels destination with native controls and a display-only chart leaf.
// Exports: PanelsView and PanelsModel.
// Dependencies: SwiftUI, PanelFixtures, PanelStore, PanelRenderer, and PanelWebModel.

import SwiftUI

struct PanelsView: View {
    @StateObject private var model = PanelsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Panels").font(.largeTitle.bold())
                    Text("A native form with a display-only chart leaf.").font(.callout).foregroundStyle(.secondary)
                }
                sampleNotice
                if let fixtures = model.fixtures, let mixedStore = model.mixedStore, let metricStore = model.metricStore {
                    MixedPanelCard(fixture: fixtures.mixed, store: mixedStore, webModel: model.webModel)
                    GroupBox("Metric fixture") {
                        PanelRenderer(spec: fixtures.metric.spec, store: metricStore, webModel: model.webModel)
                            .render(fixtures.metric.spec.root)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ContentUnavailableView("Fixtures unavailable", systemImage: "doc.questionmark")
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sampleNotice: some View {
        Label("Sample data — fixture preview only; no live agent panel is connected.", systemImage: "info.circle")
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MixedPanelCard: View {
    let fixture: PanelFixture
    @ObservedObject var store: PanelStore
    @ObservedObject var webModel: PanelWebModel

    var body: some View {
        GroupBox(fixture.title) {
            PanelRenderer(spec: fixture.spec, store: store, webModel: webModel)
                .render(fixture.spec.root)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let answer = store.submittedAnswerText {
                Text("Answer this would send").font(.headline).padding(.top, 10)
                Text(answer).font(.body.monospaced()).textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class PanelsModel: ObservableObject {
    let fixtures: PanelFixtureSet?
    let mixedStore: PanelStore?
    let metricStore: PanelStore?
    let webModel = PanelWebModel()

    init() {
        guard let fixtures = try? PanelFixtures.load() else {
            self.fixtures = nil
            mixedStore = nil
            metricStore = nil
            return
        }
        self.fixtures = fixtures
        mixedStore = PanelStore(fixture: fixtures.mixed)
        metricStore = PanelStore(fixture: fixtures.metric)
    }
}
