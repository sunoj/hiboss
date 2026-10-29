// Verifies offscreen Today decisions stay unmounted and captures the affected workspaces.
// Exports: TodayScalingWindowTests with optional light/dark compositor evidence.
// Dependencies: production MainView, LayoutProbe and existing real-window fixture support.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class TodayScalingWindowTests: XCTestCase {
    func testTodayMountsOnlyVisibleDecisionCards() async throws {
        let history = (0..<200).map { index in
            AttentionTestSupport.ask(id: MessageID(rawValue: "decision-\(index)"), options: ["Ship", "Wait"],
                sessionStatus: "waiting")
        }
        let snapshot = OverviewSnapshot(history: history, live: nil, now: .now,
            requiredInputs: history, requiredInputLoaded: true)
        XCTAssertEqual(snapshot.attention.count, 200)
        let probe = LayoutProbe()
        let window = try PerfSurveyFixtures.window(TodayView(snapshot: snapshot,
            reply: AttentionReplyState(), panels: PanelsModel(demoMode: true, autoload: false),
            isPreview: true, onChoose: { _, _ in nil }, onSession: { _ in })
            .environment(\.layoutProbe, probe))
        defer { PerfSurveyFixtures.close(window) }
        try await BoxWindowCaptureSupport.settle(window)
        let mounted = probe.anchors.keys.filter { $0.hasPrefix("today.decision.") }.count
        XCTAssertGreaterThan(mounted, 0)
        XCTAssertLessThan(mounted, 30, "Offscreen decisions must not build native card trees")
    }

    func testAffectedScreensInBothAppearances() async throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_TODAY_SCREENSHOTS"] else {
            throw XCTSkip("Screenshot output is opt-in")
        }
        let history = SessionThreadFixtures.history()
        for scheme in [ColorScheme.light, .dark] {
            for (name, destination) in [("today", OverviewDestination.today),
                ("attention", .category(.needsYou)), ("session", .session("thread-demo"))] {
                let window = try PerfSurveyFixtures.window(MainView(settings: PerfSurveyFixtures.settings(),
                    flow: OptionFlowStore(), initialDestination: destination, previewHistory: history,
                    panelsModel: PanelsModel(demoMode: true, autoload: false))
                    .environment(\.colorScheme, scheme))
                defer { PerfSurveyFixtures.close(window) }
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
                try await BoxWindowCaptureSupport.settle(window)
                try BoxWindowCaptureSupport.capture(window, directory: directory,
                    name: "\(name)-\(scheme == .light ? "light" : "dark")")
            }
        }
    }
}
