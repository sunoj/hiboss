// Drives held reads through production stores and hosted empty/list surfaces.
// Exports StableRefreshTests for Today, sessions, messages, panels, progress, and device requests.
// Dependencies: XCTest, AppKit hosting, Combine coverage, and deterministic read gates.

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import HibossKit
@testable import HibossIsland

@MainActor
final class StableRefreshTests: XCTestCase {
    func testTodayAllClearAndSidebarCountsSurviveHeldHistoryAndPanelRefresh() async throws {
        for scheme in [ColorScheme.light, .dark] { try await todayAllClear(scheme: scheme) }
    }

    private func todayAllClear(scheme: ColorScheme) async throws {
        let api = try StableReadAPI()
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        let inputs = CurrentValueSubject<RequiredInputState, Never>(
            RequiredInputState(ready: true, loaded: true))
        overview.bind(flow: flow, requiredInputs: inputs.eraseToAnyPublisher())
        flow.connect(api: api)
        defer { flow.disconnect() }
        let panels = PanelsModel(api: api, demoMode: false, autoload: false)
        panels.clockTask?.cancel()
        await panels.load()
        let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: flow,
            overviewStore: overview, previewHistory: nil, panelsModel: panels))
        let window = try await StableWindowSupport.show(host, scheme: scheme)
        defer { window.close() }
        try await waitForCondition { overview.snapshot.today.isAllClear }
        let before = overview.snapshot
        await api.hold(.history)
        await api.hold(.panels)
        let history = Task { await flow.refreshHistory() }
        let panel = Task { await panels.load() }
        await api.waitUntilHeld(.history)
        await api.waitUntilHeld(.panels)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(overview.snapshot.today.isAllClear)
        XCTAssertEqual(overview.snapshot.history, before.history)
        XCTAssertEqual(overview.snapshot.answerability.isLoaded, before.answerability.isLoaded)
        XCTAssertEqual(overview.snapshot.count(.all), before.count(.all))
        XCTAssertEqual(overview.snapshot.count(.completed), before.count(.completed))
        XCTAssertTrue(OverviewSidebar(snapshot: overview.snapshot, selection: .today,
            historyState: flow.historyState, connectionState: flow.connectionState,
            hasLoadedHistory: flow.historyLoadedAt != nil,
            onSelect: { _ in }, onSettings: {}, onRefresh: {}).countsAvailable)
        XCTAssertEqual(images(host).count, 1, "The all-clear illustration stays mounted")
        await capture(window, name: "today-all-clear-refresh-\(scheme)")
        await api.release(.history)
        await api.release(.panels)
        await history.value
        await panel.value
        await capture(window, name: "today-all-clear-settled-\(scheme)")
    }

    func testTodayAndSessionDecisionsAndReplyControlsSurviveHeldRefresh() async throws {
        for scheme in [ColorScheme.light, .dark] { try await decisions(scheme: scheme) }
    }

    private func decisions(scheme: ColorScheme) async throws {
        let question = StableSurfaceCaptureTests.question
        let api = try StableReadAPI(history: [question])
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        let inputs = CurrentValueSubject<RequiredInputState, Never>(
            RequiredInputState(messages: [question], ready: true, loaded: true))
        overview.bind(flow: flow, requiredInputs: inputs.eraseToAnyPublisher())
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.historyState == .loaded }
        for destination in [OverviewDestination.today, .session("session"), .category(.all)] {
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: flow,
                overviewStore: overview, initialDestination: destination, previewHistory: nil,
                panelsModel: PanelsModel(demoMode: true, autoload: false)))
            let window = try await StableWindowSupport.show(host, scheme: scheme)
            defer { window.close() }
            let before = overview.snapshot
            let controls = fields(host).map(\.isEnabled)
            await api.hold(.history)
            let refresh = Task { await flow.refreshHistory() }
            await api.waitUntilHeld(.history)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(overview.snapshot.today.health, before.today.health)
            XCTAssertEqual(overview.snapshot.history, before.history)
            XCTAssertEqual(overview.snapshot.today.decisions.map(\.id), [question.id])
            XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .open)
            XCTAssertTrue(overview.snapshot.answerability.permitsReply(to: question))
            XCTAssertEqual(fields(host).map(\.isEnabled), controls)
            XCTAssertFalse(overview.snapshot.today.isAllClear)
            let name = destination == .today ? "today-decision"
                : destination == .category(.all) ? "history" : "session"
            await capture(window, name: "\(name)-refresh-\(scheme)")
            await api.release(.history)
            await refresh.value
            await capture(window, name: "\(name)-settled-\(scheme)")
        }
    }

    func testEmptyHistoryAndSessionKeepTheirCompletedEmptyStateDuringRefresh() async throws {
        let api = try StableReadAPI()
        let flow = OptionFlowStore()
        flow.connect(api: api)
        defer { flow.disconnect() }
        try await waitForCondition { flow.historyState == .loaded }
        let snapshot = OverviewSnapshot(history: [], live: nil, now: .now)
        for destination in [OverviewDestination.category(.all), .session("empty")] {
            let view: AnyView = destination == .category(.all)
                ? AnyView(HistoryView(flow: flow, snapshot: snapshot, scope: destination,
                    onChoose: { _, _ in nil }, reply: AttentionReplyState()))
                : AnyView(SessionThreadView(context: SessionContext(id: "empty", snapshot: snapshot,
                    inventory: []), flow: flow, reply: AttentionReplyState(), connection: .connected,
                    onChoose: { _, _ in nil }))
            let host = NSHostingView(rootView: view)
            let window = try await StableWindowSupport.show(host)
            defer { window.close() }
            let before = spinners(host).count
            await api.hold(.history)
            let refresh = Task { await flow.refreshHistory() }
            await api.waitUntilHeld(.history)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(spinners(host).count, before, "An empty result must not become a placeholder")
            XCTAssertTrue(flow.historyMessages.isEmpty)
            await api.release(.history)
            await refresh.value
        }
    }

    func testEmptyPanelsKeepCoverageAndEmptyWallDuringRefresh() async throws {
        let api = try StableReadAPI()
        let model = PanelsModel(api: api, demoMode: false, autoload: false)
        model.clockTask?.cancel()
        await model.load()
        model.section = .needsInput
        let host = NSHostingView(rootView: DashboardPanelsSection(model: model))
        let window = try await StableWindowSupport.show(host)
        defer { window.close() }
        let height = host.fittingSize.height
        let buttons = nativeButtons(host).map(\.isEnabled)
        await api.hold(.panels)
        await api.hold(.questions)
        let refresh = Task { await model.load() }
        await api.waitUntilHeld(.panels)
        await api.waitUntilHeld(.questions)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertTrue(model.hasDisplayCoverage)
        XCTAssertTrue(model.tiles.isEmpty)
        XCTAssertEqual(nativeButtons(host).map(\.isEnabled), buttons)
        XCTAssertTrue(spinners(host).isEmpty)
        XCTAssertEqual(host.fittingSize.height, height, accuracy: 1)
        await api.release(.panels)
        await api.release(.questions)
        await refresh.value
    }

    func testProgressEmptyResultAndListControlsSurviveRefreshAndFilter() async throws {
        for scheme in [ColorScheme.light, .dark] { try await progress(scheme: scheme) }
    }

    private func progress(scheme: ColorScheme) async throws {
        for posts in [[], ProgressFixtures.posts()] {
            let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: posts,
                nextCursor: posts.isEmpty ? nil : ProgressFixtures.cursor)])
            api.projects = [ProgressProject(project: "hiboss", count: posts.count,
                lastPostAt: nil, agentId: "builder")]
            let store = ProgressFeedStore { api }
            await store.refresh()
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .progress, previewHistory: [], progressStore: store))
            let window = try await StableWindowSupport.show(host, scheme: scheme)
            defer { window.close() }
            let before = spinners(host).count
            let buttons = nativeButtons(host).map(\.isEnabled)
            for filter in [false, true] {
                api.holdsRead = true
                let refresh = Task {
                    if filter { await store.selectProject("hiboss") } else { await store.refresh() }
                }
                try await waitForCondition { api.pendingRead != nil }
                try await Task.sleep(for: .milliseconds(400))
                XCTAssertEqual(store.posts, posts)
                XCTAssertTrue(store.didLoad)
                XCTAssertEqual(spinners(host).count, before)
                XCTAssertEqual(nativeButtons(host).map(\.isEnabled), buttons)
                if !posts.isEmpty { await capture(window, name: "progress-refresh-\(scheme)") }
                api.holdsRead = false
                api.releaseRead()
                await refresh.value
                if !posts.isEmpty { await capture(window, name: "progress-settled-\(scheme)") }
            }
        }
    }

    func testDeviceEmptyResultSurvivesFailedRefreshAndHeldRetry() async throws {
        let api = try StableReadAPI()
        let model = JoinRequestsModel { api }
        await model.refresh()
        let host = NSHostingView(rootView: DeviceRequestsView(model: model,
            focus: .constant(nil), onSettings: {}))
        let window = try await StableWindowSupport.show(host)
        defer { window.close() }
        await api.fail(.joins)
        await model.refresh()
        let before = spinners(host).count
        await api.hold(.joins)
        let refresh = Task { await model.refresh() }
        await api.waitUntilHeld(.joins)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(spinners(host).count, before)
        XCTAssertTrue(model.requests.isEmpty)
        if case .failed = model.state {} else { XCTFail("Keep the cached failure annotation during retry") }
        await api.release(.joins)
        await refresh.value
    }

    private func fields(_ host: NSView) -> [NSTextField] {
        StableWindowSupport.descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    }
    private func images(_ host: NSView) -> [NSImageView] {
        StableWindowSupport.descendants(host).compactMap { $0 as? NSImageView }
    }
    private func spinners(_ host: NSView) -> [NSProgressIndicator] {
        StableWindowSupport.descendants(host).compactMap { $0 as? NSProgressIndicator }
    }
    private func nativeButtons(_ host: NSView) -> [NSButton] {
        StableWindowSupport.descendants(host).compactMap { $0 as? NSButton }
    }
    private func capture(_ window: NSWindow, name: String) async {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_STABILITY_REFRESH"] else { return }
        do { try await StableWindowSupport.capture(window, directory: directory, name: name) }
        catch { XCTFail("Window capture failed: \(error)") }
    }
}
