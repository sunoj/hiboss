// Exercises actual MainView observers with held panel reads and healthy message coverage.
// Exports TodayStartupCoverageTests for account replacement, sign-out, and all-clear ordering.
// Dependencies: AppKit hosting, Combine, HibossKit, and TodayStartupAPI.

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import HibossKit
@testable import HibossIsland

@MainActor
final class TodayStartupCoverageTests: XCTestCase {
    func testAccountReplacementInvalidatesBeforeOverlappingLoad() async throws {
        try await accountChange(signOut: false)
    }

    func testSignOutInvalidatesBeforeOverlappingLoad() async throws {
        try await accountChange(signOut: true)
    }

    private func accountChange(signOut: Bool) async throws {
        let api = try TodayStartupAPI()
        await api.setPopulated(true)
        let settings = try await makeSettings()
        let model = makeModel(api)
        let window = host(settings: settings, model: model)
        defer { window.close() }
        await api.waitForPanels()
        let generation = model.questionnaireGeneration
        await api.setPopulated(false)
        if signOut {
            settings.serverAddress = ""
            await settings.loadToken()
        } else {
            let config = try XCTUnwrap(settings.activeClientConfig)
            _ = try settings.activateDeviceToken("account-b", replacing: config)
        }
        for _ in 0..<100 { await Task.yield() }
        window.contentView?.layoutSubtreeIfNeeded()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertGreaterThan(model.questionnaireGeneration, generation,
                             "The actual Mac config observer must invalidate old work synchronously")
        await api.releasePanels()
        try await waitForCondition { !model.isFetching && model.reconciliationTask == nil }
        XCTAssertTrue(model.tiles.isEmpty, "The held previous-account panel must never be installed")
        let reads = await api.panelReads
        XCTAssertEqual(reads, 2, "The coalesced load must use the new account generation")
    }

    func testOverviewRemainsIncompleteWhilePanelsAreHeldOrFailed() async throws {
        let api = try TodayStartupAPI()
        let model = makeModel(api)
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        let inputs = CurrentValueSubject<RequiredInputState, Never>(
            RequiredInputState(ready: true, loaded: true))
        overview.bind(flow: flow, requiredInputs: inputs.eraseToAnyPublisher())
        flow.connect(api: api)
        defer { flow.disconnect() }
        let window = host(settings: try await makeSettings(), model: model, flow: flow, overview: overview)
        defer { window.close() }
        await api.waitForPanels()
        try await waitForCondition { model.hasCompleteQuestionnaires && flow.historyState == .loaded
            && flow.connectionState == .connected }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(overview.snapshot.today.coverageComplete, "Held panels are an outstanding source")
        await api.failPanels()
        await api.releasePanels()
        try await waitForCondition { model.failureMessage != nil }
        XCTAssertFalse(overview.snapshot.today.isAllClear, "A failed panel list cannot certify Today")
    }

    func testOverviewWaitsForLivePanelAndObservesCoverageLossWithoutClock() async throws {
        let api = try TodayStartupAPI()
        await api.setPopulated(true)
        let model = makeModel(api)
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        let inputs = CurrentValueSubject<RequiredInputState, Never>(
            RequiredInputState(ready: true, loaded: true))
        overview.bind(flow: flow, requiredInputs: inputs.eraseToAnyPublisher())
        flow.connect(api: api)
        defer { flow.disconnect() }
        let window = host(settings: try await makeSettings(), model: model, flow: flow, overview: overview)
        defer { window.close() }
        await api.waitForPanels()
        await api.releasePanels()
        try await waitForCondition { !model.isFetching && model.loadState == .loaded
            && flow.historyState == .loaded && flow.connectionState == .connected }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(overview.snapshot.today.isAllClear, "An HTTP checkpoint is not live panel coverage")
        let tile = try XCTUnwrap(model.tiles.first)
        model.receive(.snapshot(PanelRelaySnapshot(panelID: tile.id, definitionRevision: 1,
            epoch: "live", sequence: 0, task: .object([:]))), for: tile.id)
        try await waitForCondition { overview.snapshot.today.isAllClear }
        model.liveSubscriptions.remove(tile.id)
        try await waitForCondition { !overview.snapshot.today.isAllClear }
    }

    private func makeModel(_ api: TodayStartupAPI) -> PanelsModel {
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        return model
    }

    private func makeSettings() async throws -> AppSettings {
        let name = "TodayStartupCoverageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults, keychain: StartupTokenStore())
        settings.serverAddress = "https://example.invalid"
        await settings.loadToken()
        return settings
    }

    private func host(settings: AppSettings, model: PanelsModel, flow: OptionFlowStore = OptionFlowStore(),
                      overview: OverviewStore = OverviewStore()) -> NSWindow {
        let view = NSHostingView(rootView: MainView(settings: settings, flow: flow, overviewStore: overview,
            previewHistory: nil, boxProvider: { nil }, progressProvider: { nil }, panelsModel: model))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1000, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        return window
    }
}

private struct StartupTokenStore: TokenStoring {
    func read() throws -> String? { "account-a" }
    func write(_ token: String) throws {}
}
