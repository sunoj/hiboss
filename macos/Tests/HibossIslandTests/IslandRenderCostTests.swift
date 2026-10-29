// Guards the live question surface against per-frame redraw cost.
// Exports: IslandRenderCostTests.
// Dependencies: AppKit, SwiftUI, XCTest, and the production Island stores.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class IslandRenderCostTests: XCTestCase {
    func testExpiringQuestionDoesNotContinuouslyLayout() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: "IslandRenderCostTests")!
        defer { defaults.removePersistentDomain(forName: "IslandRenderCostTests") }
        let settings = AppSettings(defaults: defaults)
        settings.playsSound = false
        let message = OptionMessage(id: "render-cost", body: "Choose a path",
            metadata: MessageMetadata(options: ["Ship", "Hold"], defaultOption: "Hold"),
            expiresAt: ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(300)))
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let overview = islandTestOverview(flow: flow)
        let controller = IslandPanelController(flow: flow, settings: settings, overview: overview)
        defer { flow.disconnect(); controller.panel.close(); controller.optionWindow.close() }
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await Task.sleep(for: .seconds(1))
        let start = processCPUSeconds()
        try await Task.sleep(for: .seconds(3))
        // A per-frame surface update measured ~97% of a core; a static band measures under 1%.
        XCTAssertLessThan((processCPUSeconds() - start) / 3, 0.25,
            "The expiry band must not drive per-frame SwiftUI updates")
        try await captureBandStates(controller.panel)
    }

    private func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let time = [usage.ru_utime, usage.ru_stime]
        return time.reduce(0) { $0 + Double($1.tv_sec) + Double($1.tv_usec) / 1_000_000 }
    }

    private func captureBandStates(_ panel: NSWindow) async throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_EXPIRY_SNAPSHOTS"] else { return }
        let band = try XCTUnwrap(findBand(in: try XCTUnwrap(panel.contentView)))
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for (name, fraction) in [("calm", 1.0), ("urgent", 0.14)] {
            let now = Date()
            band.progress = ExpiryProgress(startedAt: now.addingTimeInterval(-300 * (1 - fraction)),
                expiresAt: now.addingTimeInterval(300 * fraction))
            band.resynchronize()
            try await Task.sleep(for: .milliseconds(150))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(panel.windowNumber), "\(directory)/\(name).png"]
            try capture.run()
            try await waitForCondition { !capture.isRunning }
            XCTAssertEqual(capture.terminationStatus, 0)
        }
    }

    private func findBand(in view: NSView) -> ExpiryBandView? {
        if let band = view as? ExpiryBandView { return band }
        return view.subviews.lazy.compactMap { self.findBand(in: $0) }.first
    }
}
