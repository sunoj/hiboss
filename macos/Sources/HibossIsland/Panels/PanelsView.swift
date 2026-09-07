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
                    Text("Reference panels for real task shapes.").font(.callout).foregroundStyle(.secondary)
                }
                sampleNotice
                if let fixture = model.currentFixture, let store = model.currentStore {
                    pager
                    PanelCard(fixture: fixture, store: store, webModel: model.webModel)
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

    private var pager: some View {
        HStack {
            Button("Previous") { model.showPrevious() }.disabled(!model.canShowPrevious)
            Text("Example \(model.selectedIndex + 1) of \(model.fixtureCount)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button("Next") { model.showNext() }.disabled(!model.canShowNext)
        }
    }
}

private struct PanelCard: View {
    let fixture: PanelFixture
    @ObservedObject var store: PanelStore
    @ObservedObject var webModel: PanelWebModel

    var body: some View {
        GroupBox(fixture.title) {
            PanelRenderer(spec: fixture.spec, store: store, webModel: webModel)
                .render(fixture.spec.root)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let answer = store.submittedAnswerText {
                Text("Captured submission").font(.headline).padding(.top, 10)
                if store.submissionWasEdited {
                    Text("Form edited since submission; this is the previous answer, not the current draft.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text(answer).font(.body.monospaced()).textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
final class PanelsModel: ObservableObject {
    let fixtures: PanelFixtureSet?
    private let stores: [PanelStore]
    @Published private(set) var selectedIndex = 0
    let webModel = PanelWebModel()

    init() {
        guard let fixtures = try? PanelFixtures.load() else {
            self.fixtures = nil
            stores = []
            return
        }
        self.fixtures = fixtures
        stores = fixtures.all.map(PanelStore.init)
    }

    var currentFixture: PanelFixture? { fixtures?.all[safe: selectedIndex] }
    var currentStore: PanelStore? { stores[safe: selectedIndex] }
    var fixtureCount: Int { fixtures?.all.count ?? 0 }
    var canShowPrevious: Bool { selectedIndex > 0 }
    var canShowNext: Bool { selectedIndex + 1 < fixtureCount }

    func showPrevious() {
        guard canShowPrevious else { return }
        selectedIndex -= 1
    }

    func showNext() {
        guard canShowNext else { return }
        selectedIndex += 1
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
