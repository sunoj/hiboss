// Guards the live question surface against timer-driven layout churn.
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
        let host = LayoutCountingHost(rootView: IslandView(flow: flow, reply: controller.reply,
            overview: overview))
        host.sizingOptions = []
        controller.panel.contentView = host
        try await Task.sleep(for: .seconds(1))
        host.layoutCount = 0
        try await Task.sleep(for: .seconds(2))
        XCTAssertLessThanOrEqual(host.layoutCount, 6, "Expiry animation must not lay out the surface")
        try await captureBandStates(controller.panel)
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

@MainActor
private final class LayoutCountingHost: NSHostingView<IslandView> {
    var layoutCount = 0

    override func layout() {
        layoutCount += 1
        super.layout()
    }
}
