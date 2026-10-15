// Reproduces presentation after a collapsed drop target or a manually widened window.
// Extends the drop-reveal and presentation regression suites with live window checks.
// Dependencies: AppKit, SwiftUI, XCTest, and production presentation stores.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

extension IslandDropRevealIntegrationTests {
    func testQuestionAfterDropTargetHidesRestoresPresentationSize() async throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var point = NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 10)
        let (controller, flow) = try widthTestController(mode: .island, pointerLocation: { point })
        defer {
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        let reveal = try XCTUnwrap(controller.dropReveal)
        reveal.pointerMoved(to: point, dragging: false)
        try await waitForCondition { controller.panel.isVisible }
        XCTAssertEqual(controller.panel.frame.width, screen.islandGeometry.collapsedFrame.width)
        point.y -= 100
        reveal.pointerMoved(to: point, dragging: false)
        try await waitForCondition { !controller.panel.isVisible }
        let message = OptionMessage.fixture(id: "after-drop-hide", options: ["Ship", "Hold"])
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { controller.panel.isVisible && controller.naturalHeight != nil }
        try assertPresentationFits(controller, flow: flow, mode: .island)
    }
}

extension IslandPresentationRegressionTests {
    func testNextQuestionRestoresWidenedWindowAndComesFront() async throws {
        let (controller, flow) = try widthTestController(mode: .window)
        defer {
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        let first = OptionMessage.fixture(id: "before-window-resize", options: ["Ship"])
        let next = OptionMessage.fixture(id: "after-window-resize", options: ["Ship", "Hold"])
        flow.connect(api: ScriptedBossAPI(messages: [first, next]))
        try await waitForCondition { controller.optionWindow.isVisible && controller.naturalHeight != nil }
        controller.optionWindow.setContentSize(NSSize(width: 680, height: 500))
        XCTAssertEqual(controller.optionWindow.contentView?.frame.width, 680)
        controller.optionWindow.orderOut(nil)
        flow.skip()
        try await waitForCondition {
            flow.activeMessage?.id == next.id && controller.optionWindow.isVisible
                && controller.naturalHeight != nil
        }
        try assertPresentationFits(controller, flow: flow, mode: .window)
    }
}

@MainActor
private func widthTestController(mode: OptionPresentationMode,
                                 pointerLocation: @escaping () -> NSPoint = { .zero }) throws
    -> (IslandPanelController, OptionFlowStore) {
    _ = NSApplication.shared
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "PresentationWidth.\(UUID().uuidString)"))
    let settings = AppSettings(defaults: defaults)
    settings.playsSound = false
    settings.presentationMode = mode
    let flow = OptionFlowStore(reconnectDelay: .seconds(60))
    return (IslandPanelController(flow: flow, settings: settings,
        overview: islandTestOverview(flow: flow), pointerLocation: pointerLocation), flow)
}

@MainActor
private func assertPresentationFits(_ controller: IslandPanelController, flow: OptionFlowStore,
                                    mode: OptionPresentationMode) throws {
    let window = mode == .island ? controller.panel : controller.optionWindow
    let inset = mode == .island ? (window.screen?.islandGeometry.expandedTopInset ?? 0) : 0
    let natural = NSHostingView(rootView: IslandView(flow: flow, reply: controller.reply,
        overview: controller.overview,
        surfaceStyle: mode == .island ? .island : .window, topInset: inset)
        .frame(width: AppConstants.Island.width).fixedSize(horizontal: false, vertical: true))
    natural.layoutSubtreeIfNeeded()
    let host = try XCTUnwrap(window.contentView)
    XCTAssertEqual(host.frame.width, AppConstants.Island.width, accuracy: 0.5)
    XCTAssertEqual(host.frame.height, natural.fittingSize.height, accuracy: 4)
    try assertIslandQuestionIsVisible(in: window, fullyVisible: true)
    let field = try XCTUnwrap(editableFields(host).first)
    XCTAssertTrue(host.bounds.contains(host.convert(field.bounds, from: field)))
}

@MainActor
private func editableFields(_ view: NSView) -> [NSTextField] {
    view.subviews.flatMap { child in
        if let field = child as? NSTextField, field.isEditable { return [field] }
        return editableFields(child)
    }
}
