// Exercises the pure reveal policy and native hidden-panel integration.
// Covers dwell, drag, holds, presentation overrides and multi-screen geometry.
// Dependencies: XCTest, AppKit and the Island drop reveal types.

import AppKit
import ApplicationServices
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

final class IslandDropRevealPolicyTests: XCTestCase {
    func testDwellRevealsOnlyAfterThreeTenthsOfASecond() {
        var policy = idle()
        policy.send(.pointer(inHotZone: true, dragging: false), at: 10)
        XCTAssertEqual(policy.visibility, .hidden)
        XCTAssertEqual(policy.nextDeadline, 10.3)
        policy.send(.deadline, at: 10.29)
        XCTAssertEqual(policy.visibility, .hidden)
        policy.send(.deadline, at: 10.3)
        XCTAssertEqual(policy.visibility, .dropTarget)
        XCTAssertNil(policy.nextDeadline)
    }

    func testQuickPassThroughCancelsDwellAndNextEntryStartsAgain() {
        var policy = idle()
        policy.send(.pointer(inHotZone: true, dragging: false), at: 10)
        policy.send(.pointer(inHotZone: false, dragging: false), at: 10.2)
        policy.send(.deadline, at: 11)
        XCTAssertEqual(policy.visibility, .hidden)
        XCTAssertNil(policy.nextDeadline)
        policy.send(.pointer(inHotZone: true, dragging: false), at: 12)
        XCTAssertEqual(policy.nextDeadline, 12.3)
    }

    func testDragRevealsImmediatelyAndReleaseDoesNotHideInside() {
        var policy = idle()
        policy.send(.pointer(inHotZone: true, dragging: true), at: 10)
        XCTAssertEqual(policy.visibility, .dropTarget)
        XCTAssertNil(policy.nextDeadline)
        policy.send(.pointer(inHotZone: true, dragging: false), at: 10.01)
        XCTAssertEqual(policy.visibility, .dropTarget)
    }

    func testDelayedHideAndReentryCancelsHide() {
        var policy = revealed()
        policy.send(.pointer(inHotZone: false, dragging: false), at: 11)
        policy.send(.deadline, at: 11.99)
        XCTAssertEqual(policy.visibility, .dropTarget)
        XCTAssertEqual(policy.nextDeadline, 12)
        policy.send(.pointer(inHotZone: true, dragging: false), at: 11.99)
        XCTAssertNil(policy.nextDeadline)
        policy.send(.pointer(inHotZone: false, dragging: false), at: 13)
        policy.send(.deadline, at: 14)
        XCTAssertEqual(policy.visibility, .hidden)
        XCTAssertNil(policy.nextDeadline)
    }

    func testPopoverAndUploadEachKeepBarUntilBothEnd() {
        var policy = revealed()
        policy.send(.activity(popover: true, uploading: false), at: 10)
        policy.send(.pointer(inHotZone: false, dragging: false), at: 11)
        policy.send(.deadline, at: 12)
        XCTAssertEqual(policy.visibility, .dropTarget)
        XCTAssertNil(policy.nextDeadline)
        policy.send(.activity(popover: false, uploading: true), at: 13)
        XCTAssertEqual(policy.visibility, .dropTarget)
        policy.send(.activity(popover: false, uploading: false), at: 14)
        XCTAssertEqual(policy.visibility, .hidden)
    }

    func testEndingHoldBeforeHideDeadlinePreservesRemainingDelay() {
        var policy = revealed()
        policy.send(.pointer(inHotZone: false, dragging: false), at: 11)
        policy.send(.activity(popover: true, uploading: true), at: 11.1)
        policy.send(.activity(popover: false, uploading: false), at: 11.5)
        XCTAssertEqual(policy.visibility, .dropTarget)
        XCTAssertEqual(policy.nextDeadline, 12)
    }

    func testQuestionOverridesDwellAndHideThenClearsToHidden() {
        var policy = idle()
        policy.send(.pointer(inHotZone: true, dragging: false), at: 10)
        policy.send(.presentation(island: true, question: true), at: 10.1)
        policy.send(.pointer(inHotZone: false, dragging: false), at: 11)
        XCTAssertEqual(policy.visibility, .question)
        XCTAssertNil(policy.nextDeadline)
        policy.send(.presentation(island: true, question: false), at: 12)
        XCTAssertEqual(policy.visibility, .hidden)
        policy = revealed()
        policy.send(.pointer(inHotZone: false, dragging: false), at: 11)
        policy.send(.presentation(island: true, question: true), at: 11.1)
        policy.send(.deadline, at: 12)
        XCTAssertEqual(policy.visibility, .question)
    }

    func testWindowModeNeverRevealsAndSwitchingBackStartsHidden() {
        var policy = revealed()
        policy.send(.presentation(island: false, question: true), at: 11)
        policy.send(.pointer(inHotZone: true, dragging: true), at: 12)
        XCTAssertEqual(policy.visibility, .hidden)
        XCTAssertNil(policy.nextDeadline)
        policy.send(.presentation(island: true, question: false), at: 13)
        XCTAssertEqual(policy.visibility, .hidden)
    }

    private func idle() -> IslandDropRevealPolicy {
        var policy = IslandDropRevealPolicy()
        policy.send(.presentation(island: true, question: false), at: 0)
        return policy
    }

    private func revealed() -> IslandDropRevealPolicy {
        var policy = idle()
        policy.send(.pointer(inHotZone: true, dragging: true), at: 10)
        return policy
    }
}

@MainActor
final class IslandDropRevealIntegrationTests: XCTestCase {
    func testIdlePanelIsOrderedOutAndHostingSizingRemainsDisabled() throws {
        let (controller, _) = try controller()
        defer { controller.panel.close() }
        XCTAssertFalse(controller.panel.isVisible)
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        XCTAssertEqual(host.sizingOptions, [])
        let windowHost = try XCTUnwrap(controller.optionWindow.contentView as? NSHostingView<IslandView>)
        XCTAssertEqual(windowHost.sizingOptions, [])
    }

    func testHotZoneTracksTopCentreOnOffsetScreens() {
        for frame in [NSRect(x: 0, y: 0, width: 1440, height: 900),
            NSRect(x: -1920, y: 300, width: 1920, height: 1080)] {
            let zone = IslandDropRevealController.hotZone(on: frame)
            XCTAssertEqual(zone.size, NSSize(width: 184, height: 36))
            XCTAssertEqual(zone.midX, frame.midX)
            XCTAssertEqual(zone.maxY, frame.maxY)
            XCTAssertTrue(zone.contains(NSPoint(x: frame.midX, y: frame.maxY - 1)))
            XCTAssertFalse(zone.contains(NSPoint(x: frame.midX, y: frame.maxY - 37)))
        }
    }

    func testMouseMonitorRegistrationAndIdleEventCost() throws {
        let token = try XCTUnwrap(NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged], handler: { _ in }
        ))
        defer { NSEvent.removeMonitor(token) }
        let (controller, _) = try controller()
        defer { controller.panel.close() }
        let reveal = try XCTUnwrap(controller.dropReveal)
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<10_000 { reveal.pointerMoved(to: .zero, dragging: false) }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertFalse(controller.panel.isVisible)
        print("Island idle pointer cost: \(elapsed * 1000) ms / 10000 events; "
            + "Accessibility trusted=\(AXIsProcessTrusted()); global mouse monitor registered")
    }

    func testNativeDwellTimerAndDelayedHideWithoutFurtherMovement() async throws {
        let (controller, _) = try controller()
        defer { controller.panel.close() }
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        var point = try hotPoint()
        let reveal = IslandDropRevealController(
            panel: controller.panel, host: host, pointerLocation: { point }
        )
        reveal.setPresentation(island: true, question: false)
        let start = ProcessInfo.processInfo.systemUptime
        reveal.pointerMoved(to: point, dragging: false)
        XCTAssertFalse(controller.panel.isVisible)
        try await waitForCondition { controller.panel.isVisible }
        let dwell = ProcessInfo.processInfo.systemUptime - start
        XCTAssertGreaterThanOrEqual(dwell, 0.3)
        point.y -= 100
        let left = ProcessInfo.processInfo.systemUptime
        reveal.pointerMoved(to: point, dragging: false)
        XCTAssertTrue(controller.panel.isVisible)
        try await waitForCondition { !controller.panel.isVisible }
        let hide = ProcessInfo.processInfo.systemUptime - left
        XCTAssertGreaterThanOrEqual(hide, 1)
        print("Island one-shot timing: dwell=\(dwell) s, hide=\(hide) s")
        XCTAssertFalse(controller.panel.isVisible)
    }

    func testDragOrdersNativeDropHostImmediatelyAndWindowModeStaysHidden() throws {
        let (controller, settings) = try controller()
        defer { controller.panel.close() }
        let reveal = try XCTUnwrap(controller.dropReveal)
        let start = ProcessInfo.processInfo.systemUptime
        reveal.pointerMoved(to: try hotPoint(), dragging: true)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertEqual(controller.panel.frame.size, NSSize(width: 184, height: 36))
        XCTAssertTrue(controller.panel.contentView is BoxDropHostingView)
        print("Island drag reveal native ordering: \(elapsed * 1000) ms")
        settings.presentationMode = .window
        reveal.pointerMoved(to: try hotPoint(), dragging: true)
        XCTAssertFalse(controller.panel.isVisible)
        XCTAssertFalse(controller.optionWindow.isVisible)
    }

    func testOpenPopoverHoldsBarAndClosingAppliesElapsedHideDeadline() async throws {
        let (controller, _) = try controller()
        defer { controller.panel.close() }
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        let reveal = try XCTUnwrap(controller.dropReveal)
        var point = try hotPoint()
        reveal.pointerMoved(to: point, dragging: true)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("A reference", forType: .string)
        host.receive(pasteboard)
        XCTAssertTrue(host.popover.isShown)
        point.y -= 100
        reveal.pointerMoved(to: point, dragging: false)
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertTrue(controller.panel.isVisible)
        host.popover.close()
        try await waitForCondition { !controller.panel.isVisible }
        XCTAssertNil(host.dropStore)
    }

    func testQuestionArrivesDuringDwellAndClearingOrdersPanelOut() async throws {
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let (controller, _) = try controller(flow: flow)
        defer {
            flow.disconnect()
            controller.panel.close()
        }
        controller.dropReveal?.pointerMoved(to: try hotPoint(), dragging: false)
        let message = OptionMessage.fixture(id: "reveal-question", options: ["Done"])
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        XCTAssertTrue(controller.panel.isVisible)
        flow.skip()
        try await waitForCondition { flow.activeMessage == nil }
        XCTAssertFalse(controller.panel.isVisible)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(controller.panel.isVisible)
    }

    private func hotPoint() throws -> NSPoint {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        return NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 10)
    }

    private func controller(flow: OptionFlowStore = OptionFlowStore()) throws
        -> (IslandPanelController, AppSettings) {
        _ = NSApplication.shared
        let suite = "IslandDropRevealTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, keychain: RevealTokenStore())
        settings.playsSound = false
        return (IslandPanelController(flow: flow, settings: settings), settings)
    }
}

private struct RevealTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
