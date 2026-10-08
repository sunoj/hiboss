// Exercises notch-aware reveal, question sizing and pointer-driven screen transitions.
// Exports: IslandNotchIntegrationTests with injected screen and pointer values.
// Dependencies: XCTest, AppKit hosting, OptionFlowStore and IslandNotchFixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class IslandNotchIntegrationTests: XCTestCase {
    func testDraggingIntoSecondaryNotchRevealsBarAndMovingToPlainScreenRestoresOldGeometry() throws {
        let notch = IslandNotchFixtures.secondary
        let plain = IslandNotchFixtures.plain
        var point = CGPoint(x: notch.screenFrame.midX, y: notch.screenFrame.maxY - 1)
        let controller = try controller(screens: [plain, notch], pointer: { point })
        defer { controller.panel.close() }
        let reveal = try XCTUnwrap(controller.dropReveal)
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        reveal.pointerMoved(to: point, dragging: true)
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertEqual(controller.panel.frame, notch.collapsedFrame)
        XCTAssertEqual(host.rootView.topInset, 32)
        XCTAssertEqual(host.sizingOptions, [])

        point = CGPoint(x: plain.screenFrame.midX, y: plain.screenFrame.maxY - 1)
        reveal.pointerMoved(to: point, dragging: true)
        XCTAssertEqual(controller.panel.frame, plain.collapsedFrame)
        XCTAssertEqual(host.rootView.topInset, 0)

        point = CGPoint(x: notch.screenFrame.midX, y: notch.screenFrame.maxY - 50)
        reveal.pointerMoved(to: point, dragging: true)
        XCTAssertEqual(controller.panel.frame, notch.collapsedFrame)
        XCTAssertEqual(host.rootView.topInset, 32)
    }

    func testDwellInsideNotchRevealsAndLeavingVisibleBarHidesWithoutFurtherMovement() async throws {
        let notch = IslandNotchFixtures.macBook14
        var point = CGPoint(x: notch.screenFrame.midX, y: notch.screenFrame.maxY - 1)
        let controller = try controller(screens: [notch], pointer: { point })
        defer { controller.panel.close() }
        let reveal = try XCTUnwrap(controller.dropReveal)
        reveal.pointerMoved(to: point, dragging: false)
        XCTAssertFalse(controller.panel.isVisible)
        try await waitForCondition { controller.panel.isVisible }
        XCTAssertEqual(controller.panel.frame, notch.collapsedFrame)
        point.y = notch.collapsedFrame.minY + 10
        reveal.pointerMoved(to: point, dragging: false)
        XCTAssertTrue(controller.panel.isVisible)
        point.y = notch.collapsedFrame.minY - 1
        reveal.pointerMoved(to: point, dragging: false)
        try await waitForCondition { !controller.panel.isVisible }
    }

    func testQuestionAddsNotchInsetAndStaysOnItsDisplayWhenPointerCrossesDisplays() async throws {
        let plain = IslandNotchFixtures.plain
        let notch = IslandNotchFixtures.secondary
        var point = CGPoint(x: notch.screenFrame.midX, y: notch.screenFrame.maxY - 10)
        let message = OptionMessage.fixture(id: "notched-question", options: ["Ship", "Wait"])
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let controller = try controller(flow: flow, screens: [plain, notch], pointer: { point })
        defer {
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await settle(controller.panel)
        let contentHeight = OptionPanelLayout.expandedHeight(for: message)
        assertFrame(controller.panel.frame, equals: notch.expandedFrame(contentHeight: contentHeight))
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        XCTAssertEqual(host.rootView.topInset, 32)
        try assertReplyFits(controller.panel, below: 32)

        let originalFrame = controller.panel.frame
        point = CGPoint(x: plain.screenFrame.midX, y: plain.screenFrame.maxY - 1)
        controller.dropReveal?.pointerMoved(to: point, dragging: false)
        try await settle(controller.panel)
        XCTAssertEqual(controller.panel.frame, originalFrame)
        XCTAssertEqual(host.rootView.topInset, 32)
        controller.dropReveal?.pointerMoved(to: point, dragging: true)
        XCTAssertEqual(controller.panel.frame, originalFrame)
        XCTAssertEqual(host.rootView.topInset, 32)

        flow.skip()
        try await waitForCondition { flow.activeMessage == nil }
        XCTAssertFalse(controller.panel.isVisible)
        controller.dropReveal?.pointerMoved(to: point, dragging: true)
        XCTAssertEqual(controller.panel.frame, plain.collapsedFrame)
        XCTAssertEqual(host.rootView.topInset, 0)
    }

    func testQuestionRelayoutUsesItsDisplayAfterResolutionChangeAndFallsBackAfterUnplug() async throws {
        let plain = IslandNotchFixtures.plain
        let notch = IslandNotchFixtures.secondary
        var screens = [plain, notch]
        var point = CGPoint(x: notch.screenFrame.midX, y: notch.screenFrame.maxY - 10)
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let controller = IslandPanelController(flow: flow, settings: try settings(),
            screens: { screens }, pointerLocation: { point })
        defer {
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        let message = OptionMessage.fixture(id: "resized-question", options: ["Ship", "Wait"])
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await settle(controller.panel)
        point = CGPoint(x: plain.screenFrame.midX, y: plain.screenFrame.midY)
        controller.dropReveal?.pointerMoved(to: point, dragging: false)
        let resized = IslandGeometry(screenFrame: CGRect(x: -1728, y: 300, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 651, height: 32),
            auxiliaryTopRightArea: CGRect(x: 861, y: 950, width: 651, height: 32))
        screens = [plain, resized]
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        let height = OptionPanelLayout.expandedHeight(for: message)
        XCTAssertEqual(controller.panel.frame, resized.expandedFrame(contentHeight: height))
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        XCTAssertEqual(host.rootView.topInset, 32)
        screens = [plain]
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        XCTAssertEqual(controller.panel.frame, plain.expandedFrame(contentHeight: height))
        XCTAssertEqual(host.rootView.topInset, 0)
    }

    func testQuestionDisplayIDSurvivesChangedOriginAndResolution() async throws {
        let plain = IslandNotchFixtures.plain
        let frame = IslandNotchFixtures.secondary.screenFrame
        let original = IslandGeometry(screenFrame: frame, safeAreaTop: 32, displayID: 42)
        var screens = [plain, original]
        var point = CGPoint(x: frame.midX, y: frame.maxY - 10)
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let controller = IslandPanelController(flow: flow, settings: try settings(),
            screens: { screens }, pointerLocation: { point })
        defer {
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        let message = OptionMessage.fixture(id: "moved-display-question", options: ["Ship", "Wait"])
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await settle(controller.panel)
        point = CGPoint(x: plain.screenFrame.midX, y: plain.screenFrame.midY)
        controller.dropReveal?.pointerMoved(to: point, dragging: false)
        let resized = IslandGeometry(screenFrame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
            safeAreaTop: 32, displayID: 42)
        let replacement = IslandGeometry(screenFrame: frame, displayID: 43)
        screens = [plain, replacement, resized]
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        XCTAssertEqual(controller.panel.frame,
            resized.expandedFrame(contentHeight: OptionPanelLayout.expandedHeight(for: message)))
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        XCTAssertEqual(host.rootView.topInset, 32)
    }

    func testLongNotchedQuestionRetainsCapAndVisibleReplyWhileWindowModeHasNoInset() async throws {
        let notch = IslandNotchFixtures.macBook16
        let message = OptionMessage(id: "notched-long-question",
            body: String(repeating: "A detailed question must remain readable. ", count: 150),
            metadata: MessageMetadata(options: ["Ship", "Wait"]))
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let settings = try settings()
        let controller = IslandPanelController(flow: flow, settings: settings,
            screens: { [notch] }, pointerLocation: { CGPoint(x: 864, y: 1100) })
        defer {
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await settle(controller.panel)
        XCTAssertEqual(controller.panel.frame.height, notch.visibleFrame.height * 0.8, accuracy: 1)
        try assertReplyFits(controller.panel, below: 32)
        let host = try XCTUnwrap(controller.panel.contentView)
        let scroll = try XCTUnwrap(descendants(host, type: NSScrollView.self).first)
        XCTAssertGreaterThan(scroll.documentView?.frame.height ?? 0, scroll.contentView.bounds.height)
        XCTAssertTrue(host.bounds.contains(host.convert(scroll.bounds, from: scroll)))

        settings.presentationMode = .window
        try await settle(controller.optionWindow)
        let windowHost = try XCTUnwrap(controller.optionWindow.contentView as? NSHostingView<IslandView>)
        XCTAssertEqual(windowHost.rootView.topInset, 0)
        XCTAssertEqual(windowHost.sizingOptions, [])
        XCTAssertEqual(windowHost.frame.height, notch.visibleFrame.height * 0.8, accuracy: 1)
        try assertReplyFits(controller.optionWindow, below: 0)
    }

    func testScreenParameterChangeRefreshesGeometryWithoutPointerMovement() throws {
        let notch = IslandNotchFixtures.macBook14
        let plain = IslandGeometry(screenFrame: notch.screenFrame)
        var screens = [notch]
        let point = CGPoint(x: notch.screenFrame.midX, y: notch.screenFrame.maxY - 10)
        let settings = try settings()
        let controller = IslandPanelController(flow: OptionFlowStore(), settings: settings,
            screens: { screens }, pointerLocation: { point })
        defer { controller.panel.close() }
        controller.dropReveal?.pointerMoved(to: point, dragging: true)
        XCTAssertEqual(controller.panel.frame, notch.collapsedFrame)
        screens = [plain]
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        XCTAssertEqual(controller.panel.frame, plain.collapsedFrame)
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        XCTAssertEqual(host.rootView.topInset, 0)
    }

    private func controller(
        flow: OptionFlowStore = OptionFlowStore(), screens: [IslandGeometry], pointer: @escaping () -> CGPoint
    ) throws -> IslandPanelController {
        IslandPanelController(
            flow: flow, settings: try settings(), screens: { screens }, pointerLocation: pointer
        )
    }

    private func settings() throws -> AppSettings {
        _ = NSApplication.shared
        let suite = "IslandNotchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, keychain: NotchTokenStore())
        settings.playsSound = false
        return settings
    }

    private func assertFrame(_ actual: CGRect, equals expected: CGRect) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1)
    }

    private func assertReplyFits(_ window: NSWindow, below inset: CGFloat) throws {
        let host = try XCTUnwrap(window.contentView)
        let field = try XCTUnwrap(descendants(host, type: NSTextField.self).first { $0.isEditable })
        let frame = host.convert(field.bounds, from: field)
        XCTAssertTrue(host.bounds.contains(frame))
        let top = host.isFlipped ? frame.minY : host.bounds.maxY - frame.maxY
        XCTAssertGreaterThanOrEqual(top, inset)
    }

    private func descendants<T: NSView>(_ view: NSView, type: T.Type) -> [T] {
        view.subviews.flatMap { ($0 as? T).map { [$0] } ?? descendants($0, type: type) }
    }

    private func settle(_ window: NSWindow) async throws {
        try await Task.sleep(for: .seconds(AppConstants.Island.animationDuration + 0.2))
        window.contentView?.layoutSubtreeIfNeeded()
    }
}

private struct NotchTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
