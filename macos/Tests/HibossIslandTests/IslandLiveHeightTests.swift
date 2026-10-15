// Verifies live content sizing as countdown and reply feedback change.
// Exports: IslandLiveHeightTests window regressions.
// Dependencies: AppKit, SwiftUI, XCTest, and production attention stores.

import AppKit
import Combine
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class IslandLiveHeightTests: XCTestCase {
    func testCountdownCaptionFitsLiveContent() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: "IslandLiveHeightTests")!
        defer { defaults.removePersistentDomain(forName: "IslandLiveHeightTests") }
        let settings = AppSettings(defaults: defaults)
        settings.playsSound = false
        let message = OptionMessage(id: "countdown-height", body: "Choose a path",
            metadata: MessageMetadata(options: ["Ship", "Hold"], defaultOption: "Hold"),
            expiresAt: ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(300)))
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let overview = islandTestOverview(flow: flow)
        let controller = IslandPanelController(flow: flow, settings: settings, overview: overview)
        defer {
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await Task.sleep(for: .milliseconds(700))
        let natural = NSHostingView(rootView: IslandView(flow: flow, reply: controller.reply,
            overview: overview).frame(width: AppConstants.Island.width)
            .fixedSize(horizontal: false, vertical: true))
        natural.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.panel.frame.height, natural.fittingSize.height, accuracy: 4)
        XCTAssertFalse(containsScrollView(try XCTUnwrap(controller.panel.contentView)))
        try assertIslandQuestionIsVisible(in: controller.panel)
        try await assertCountdownTickIsStable(controller)
        try await assertCaptionDisappears(controller, overview: overview, message: message)
        try await assertFailedReplyGrows(controller, flow: flow, overview: overview)
        settings.presentationMode = .window
        try await assertWindowFits(controller, flow: flow, overview: overview)
    }

    private func assertWindowFits(_ controller: IslandPanelController,
                                  flow: OptionFlowStore, overview: OverviewStore) async throws {
        try await waitForCondition { controller.optionWindow.isVisible }
        let natural = NSHostingView(rootView: IslandView(flow: flow, reply: controller.reply,
            overview: overview, surfaceStyle: .window).frame(width: AppConstants.Island.width)
            .fixedSize(horizontal: false, vertical: true))
        natural.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.optionWindow.contentView?.frame.height ?? 0,
            natural.fittingSize.height, accuracy: 4)
        try assertIslandQuestionIsVisible(in: controller.optionWindow)
        let host = try XCTUnwrap(controller.optionWindow.contentView)
        let field = try XCTUnwrap(editors(host).first)
        XCTAssertTrue(host.bounds.contains(host.convert(field.bounds, from: field)))
    }

    private func assertCountdownTickIsStable(_ controller: IslandPanelController) async throws {
        let counter = ResizeCounter()
        let observation = NotificationCenter.default.publisher(for: NSWindow.didResizeNotification,
            object: controller.panel).sink { _ in counter.count += 1 }
        defer { observation.cancel() }
        let frame = controller.panel.frame
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(controller.panel.frame, frame)
        XCTAssertEqual(counter.count, 0, "A countdown tick must not touch the frame")
    }

    private func assertCaptionDisappears(_ controller: IslandPanelController,
                                        overview: OverviewStore, message: OptionMessage) async throws {
        let oldHeight = controller.panel.frame.height
        let expired = OptionMessage(id: message.id, body: message.body, metadata: message.metadata)
        let question = TodayProjection.historyMessage(from: expired)
        overview.update(history: [question], live: nil, now: .now, health: .live(checkedAt: .now),
            coverageComplete: true, requiredInputs: [question], requiredInputLoaded: true)
        try await waitForCondition { controller.panel.frame.height < oldHeight }
        try assertMatchesLive(controller, flow: OptionFlowStore(), overview: overview)
        try assertIslandQuestionIsVisible(in: controller.panel)
    }

    private func assertFailedReplyGrows(_ controller: IslandPanelController,
                                       flow: OptionFlowStore, overview: OverviewStore) async throws {
        let id = try XCTUnwrap(flow.activeMessage?.id)
        let oldHeight = controller.panel.frame.height
        controller.reply.drafts[id] = "Keep my answer"
        await controller.reply.send("Keep my answer", for: id) { _, _ in .failed("Unavailable") }
        try await waitForCondition { controller.panel.frame.height > oldHeight }
        try assertMatchesLive(controller, flow: flow, overview: overview)
        try assertIslandQuestionIsVisible(in: controller.panel)
        let host = try XCTUnwrap(controller.panel.contentView)
        let field = try XCTUnwrap(editors(host).first)
        XCTAssertTrue(host.bounds.contains(host.convert(field.bounds, from: field)))
    }

    private func assertMatchesLive(_ controller: IslandPanelController,
                                   flow: OptionFlowStore, overview: OverviewStore) throws {
        let natural = NSHostingView(rootView: IslandView(flow: flow, reply: controller.reply,
            overview: overview).frame(width: AppConstants.Island.width)
            .fixedSize(horizontal: false, vertical: true))
        natural.layoutSubtreeIfNeeded()
        XCTAssertEqual(controller.panel.frame.height, natural.fittingSize.height, accuracy: 4)
    }

    private func editors(_ view: NSView) -> [NSTextField] {
        view.subviews.flatMap { child in
            if let field = child as? NSTextField, field.isEditable { return [field] }
            return editors(child)
        }
    }

    private func containsScrollView(_ view: NSView) -> Bool {
        view is NSScrollView || view.subviews.contains(where: containsScrollView)
    }
}

@MainActor
private final class ResizeCounter {
    var count = 0
}
