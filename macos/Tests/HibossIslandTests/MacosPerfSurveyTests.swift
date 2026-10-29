// Opt-in real-window CPU survey: skipped in normal tiers to avoid desktop takeover and slow suites.
// Exports: MacosPerfSurveyTests; scripts/perf-survey.sh sets HIBOSS_PERF_SURVEY explicitly.
// Dependencies: real MainView/Island controllers, snapshot fixtures and PerfSurveyMetrics.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class MacosPerfSurveyTests: XCTestCase {
    func testBaseline() async throws { try await baseline("Baseline before main") }

    func testZBaseline() async throws { try await baseline("Baseline after main") }

    private func baseline(_ label: String) async throws {
        try PerfSurveyMetrics.enabled()
        guard PerfSurveyMetrics.accepts(label) else { return }
        let window = try PerfSurveyFixtures.window(Text("Survey baseline"))
        defer { PerfSurveyFixtures.close(window) }
        try await PerfSurveyMetrics.measure(label, size: "empty window", window: window, update: {})
    }

    func testMainWindowSurfaces() async throws {
        try PerfSurveyMetrics.enabled()
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        for large in [false, true] {
            for (name, destination) in [("Today", OverviewDestination.today),
                ("Attention list+detail", .category(.needsYou)),
                ("Sessions sidebar+inspector+thread", .session("hiboss")),
                ("History list+inline threads", .category(.all)),
                ("Projects sidebar", .today)] {
                let label = name + (large ? " large" : " typical")
                guard PerfSurveyMetrics.accepts(label) else { continue }
                try await mainSurface(label, destination: destination, large: large, baseURL: server.baseURL)
            }
        }
    }

    private func mainSurface(_ label: String, destination: OverviewDestination,
                             large: Bool, baseURL: String) async throws {
        let count = large ? 2_000 : 30
        let sessions = large ? 200 : 3
        let history = PerfSurveyFixtures.history(count: count, sessions: sessions, baseURL: baseURL)
        let overview = OverviewStore()
        let flow = OptionFlowStore()
        let panels = try await PerfSurveyFixtures.panels()
        let window = try PerfSurveyFixtures.window(MainView(settings: PerfSurveyFixtures.settings(),
            flow: flow,
            overviewStore: overview, initialDestination: destination, previewHistory: history,
            previewSessions: PerfSurveyFixtures.inventory(count: sessions), panelsModel: panels))
        defer {
            PerfSurveyFixtures.close(window)
            flow.disconnect()
        }
        var revision = 0
        try await PerfSurveyMetrics.measure(label, size: "\(count) messages / \(sessions) sessions",
            window: window, update: {
                revision += 1
                let message = HistoryMessage(id: MessageID(rawValue: "arrival-\(revision)"),
                    body: "Validation finished. All checks passed.", agentName: "Build Agent",
                    direction: "agent_to_boss", status: "delivered", priority: "normal",
                    createdAt: AttentionTestSupport.iso(.now), sessionId: "hiboss")
                overview.update(history: history + [message], live: nil, health: .live(checkedAt: .now),
                    coverageComplete: true, requiredInputs: history, requiredInputLoaded: true)
            }, interact: {
                try self.selectSession(window: window)
            })
    }

    private func selectSession(window: NSWindow) throws {
        let root = try XCTUnwrap(window.contentView)
        let table = try XCTUnwrap(PerfSurveyMetrics.descendants(root).compactMap { $0 as? NSTableView }.first)
        // Workspace rows 0–3 and the Sessions header/search precede the first two sessions.
        let row = table.selectedRow == 6 ? 7 : 6
        XCTAssertGreaterThan(table.numberOfRows, row)
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        XCTAssertEqual(table.selectedRow, row)
    }

    func testLongSessionThread() async throws {
        try PerfSurveyMetrics.enabled()
        guard PerfSurveyMetrics.accepts("Session long thread") else { return }
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let history = PerfSurveyFixtures.history(count: 2_000, sessions: 1, baseURL: server.baseURL)
        let overview = OverviewStore()
        let flow = OptionFlowStore()
        let window = try PerfSurveyFixtures.window(MainView(settings: PerfSurveyFixtures.settings(),
            flow: flow,
            overviewStore: overview, initialDestination: .session("hiboss"), previewHistory: history,
            previewSessions: PerfSurveyFixtures.inventory(count: 1),
            panelsModel: try await PerfSurveyFixtures.panels()))
        defer {
            PerfSurveyFixtures.close(window)
            flow.disconnect()
        }
        try await PerfSurveyMetrics.measure("Session long thread", size: "2000 messages / 1 session",
            window: window, update: {
                let arrival = HistoryMessage(id: "arrival", body: "Validation complete.",
                    agentName: "Build Agent", direction: "agent_to_boss", status: "delivered",
                    priority: "normal", createdAt: AttentionTestSupport.iso(.now), sessionId: "hiboss")
                overview.update(history: history + [arrival], live: nil, health: .live(checkedAt: .now),
                    coverageComplete: true, requiredInputs: history, requiredInputLoaded: true)
            })
    }

    func testBoxAndProgress() async throws {
        try PerfSurveyMetrics.enabled()
        for large in [false, true] {
            try await box(large: large)
            try await progress(large: large)
        }
    }

    private func box(large: Bool) async throws {
        let label = "Box browser " + (large ? "large" : "typical")
        guard PerfSurveyMetrics.accepts(label) else { return }
        let items = large ? (0..<500).map {
            BoxBrowserFixtures.item("item-\($0)", text: "Review reference \($0)")
        } : BoxBrowserFixtures.items
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: items)], media: BoxBrowserFixtures.imageData())
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        await store.refresh()
        let window = try PerfSurveyFixtures.window(MainView(settings: PerfSurveyFixtures.settings(),
            flow: OptionFlowStore(), initialDestination: .box, previewHistory: [], boxProvider: { api },
            boxStore: store, boxMedia: media, panelsModel: try await PerfSurveyFixtures.panels()))
        defer {
            PerfSurveyFixtures.close(window)
            media.reset()
        }
        try await PerfSurveyMetrics.measure(label, size: "\(items.count) items", window: window,
            update: {
                await api.setPages([BoxPage(items: items + [BoxBrowserFixtures.item("arrival")])])
                await store.refresh()
            }, interact: { store.selection = items.first?.id })
    }

    private func progress(large: Bool) async throws {
        let label = "Progress " + (large ? "large" : "typical")
        guard PerfSurveyMetrics.accepts(label) else { return }
        let posts = large ? (0..<500).map { ProgressFixtures.post("post-\($0)") } : ProgressFixtures.posts()
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: posts)])
        let store = ProgressFeedStore { api }
        let window = try PerfSurveyFixtures.window(MainView(settings: PerfSurveyFixtures.settings(),
            flow: OptionFlowStore(), initialDestination: .progress, previewHistory: [],
            progressStore: store, panelsModel: try await PerfSurveyFixtures.panels()))
        defer { PerfSurveyFixtures.close(window) }
        try await PerfSurveyMetrics.measure(label, size: "\(posts.count) posts", window: window,
            update: {
                api.pages = [ProgressFeedPage(posts: [ProgressFixtures.post("arrival")] + posts)]
                await store.refresh()
            })
    }

    func testPanels() async throws {
        try PerfSurveyMetrics.enabled()
        for count in [1, 50] {
            let label = "Panels \(count)"
            guard PerfSurveyMetrics.accepts(label) else { continue }
            let panels = PanelsModel(api: try await PerfSurveyPanelsAPI(count: count),
                demoMode: false, autoload: false)
            await panels.load()
            XCTAssertEqual(panels.tiles.count, count)
            let disabled = ProcessInfo.processInfo.environment["HIBOSS_PERF_DISABLE_ANIMATIONS"] == "1"
            let window = try PerfSurveyFixtures.window(PerfSurveyPanelSurface(model: panels)
                .transaction { if disabled { $0.disablesAnimations = true } })
            defer { PerfSurveyFixtures.close(window) }
            var revision = 3.0
            try await PerfSurveyMetrics.measure(label, size: "\(panels.tiles.count) live tiles",
                window: window, update: {
                    revision += 1
                    panels.tiles.first?.store.setNumber(revision, at: "/task/done")
                }, interact: {
                    panels.open(try XCTUnwrap(panels.tiles.first).id)
                    XCTAssertNotNil(panels.selectedTile)
                })
        }
    }
}
