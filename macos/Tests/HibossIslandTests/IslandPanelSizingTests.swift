// Hosts the real option surfaces to verify AppKit window sizing.
// Covers compact questions, capped scrolling, and media options.
// Dependencies: XCTest, SwiftUI, AppKit, and IslandPanelController.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class IslandPanelSizingTests: XCTestCase {
    func testReportedQuestionKeepsWindowCloseToContentHeight() async throws {
        let message = reportedQuestion()
        XCTAssertEqual(message.body.count, 226)
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let (controller, settings) = try controller(flow: flow)
        defer {
            flow.disconnect()
            controller.panel.orderOut(nil)
            controller.optionWindow.orderOut(nil)
        }
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await settle(controller.panel)
        let content = NSHostingView(rootView: IslandView(flow: flow, reply: controller.reply)
            .frame(width: AppConstants.Island.width)
            .fixedSize(horizontal: false, vertical: true))
        content.layoutSubtreeIfNeeded()
        let contentHeight = content.fittingSize.height
        let requestedHeight = OptionPanelLayout.expandedHeight(for: message)
        let actualHeight = controller.panel.frame.height
        print("Island sizing: content=\(contentHeight), requested=\(requestedHeight), "
            + "window=\(actualHeight), min=\(controller.panel.minSize.height)")

        XCTAssertEqual(actualHeight, requestedHeight, accuracy: 1)
        XCTAssertLessThanOrEqual(abs(actualHeight - contentHeight), 50)
        let host = try XCTUnwrap(controller.panel.contentView)
        XCTAssertTrue(descendants(of: host, type: NSScrollView.self).isEmpty)
        try assertReplyIsVisible(in: controller.panel)

        settings.presentationMode = .window
        try await settle(controller.optionWindow)
        XCTAssertEqual(controller.optionWindow.contentView?.frame.height ?? 0, requestedHeight, accuracy: 1)
        try assertReplyIsVisible(in: controller.optionWindow)
    }

    func testLongQuestionScrollsInsideCapAndNextQuestionShrinks() async throws {
        let short = reportedQuestion()
        let long = OptionMessage(
            id: "long-panel-question",
            body: String(repeating: "A detailed question must remain fully readable. ", count: 150),
            metadata: short.metadata,
            expiresAt: short.expiresAt
        )
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let (controller, settings) = try controller(flow: flow)
        defer {
            flow.disconnect()
            controller.panel.orderOut(nil)
            controller.optionWindow.orderOut(nil)
        }
        flow.connect(api: ScriptedBossAPI(messages: [long, short]))
        try await waitForCondition { flow.activeMessage?.id == long.id }
        try await settle(controller.panel)
        let screen = try XCTUnwrap(controller.panel.screen)
        let cap = screen.visibleFrame.height * 0.8
        XCTAssertEqual(controller.panel.frame.height, cap, accuracy: 1)
        try assertBodyScrolls(in: controller.panel)
        try assertReplyIsVisible(in: controller.panel)

        settings.presentationMode = .window
        try await settle(controller.optionWindow)
        XCTAssertEqual(controller.optionWindow.contentView?.frame.height ?? 0, cap, accuracy: 1)
        try assertBodyScrolls(in: controller.optionWindow)
        try assertReplyIsVisible(in: controller.optionWindow)

        flow.skip()
        try await waitForCondition { flow.activeMessage?.id == short.id }
        settings.presentationMode = .island
        try await settle(controller.panel)
        XCTAssertEqual(
            controller.panel.frame.height, OptionPanelLayout.expandedHeight(for: short), accuracy: 1
        )
        let host = try XCTUnwrap(controller.panel.contentView)
        XCTAssertTrue(descendants(of: host, type: NSScrollView.self).isEmpty)
        try assertReplyIsVisible(in: controller.panel)
    }

    func testImageOptionsFitBothPresentationModes() async throws {
        let message = OptionMessage(
            id: "image-panel-question",
            body: "Choose an image",
            metadata: MessageMetadata(
                options: ["Before", "After"],
                optionMedia: [
                    OptionMedia(label: "Before", url: "file:///nonexistent-before.png"),
                    OptionMedia(label: "After", url: "file:///nonexistent-after.png")
                ]
            )
        )
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let (controller, settings) = try controller(flow: flow)
        defer {
            flow.disconnect()
            controller.panel.orderOut(nil)
            controller.optionWindow.orderOut(nil)
        }
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        try await settle(controller.panel)
        let height = OptionPanelLayout.expandedHeight(for: message)
        XCTAssertGreaterThan(height, 450)
        XCTAssertEqual(controller.panel.frame.height, height, accuracy: 1)
        try assertReplyIsVisible(in: controller.panel)

        settings.presentationMode = .window
        try await settle(controller.optionWindow)
        XCTAssertEqual(controller.optionWindow.contentView?.frame.height ?? 0, height, accuracy: 1)
        try assertReplyIsVisible(in: controller.optionWindow)
    }

    private func reportedQuestion() -> OptionMessage {
        let body = "PR431 (ALO/CLO) aidd audit done: 0 High/Med, 2 Low (ALO "
            + "blocks AMM LP mint/burn; old-ABI consumers revert on decoding ALO=3, so redeploy them first), "
            + "4 Info. Report: pendle-alo-pr431/aidd-output/20261008-103433/audit-report.md"
        return OptionMessage(
            id: "panel-height-regression",
            body: body,
            metadata: MessageMetadata(options: [
                "A: Write English PR review comment", "B: Publish to HackNote", "C: Done"
            ]),
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300))
        )
    }

    private func controller(flow: OptionFlowStore) throws -> (IslandPanelController, AppSettings) {
        _ = NSApplication.shared
        let suite = "IslandPanelSizingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults, keychain: SizingTokenStore())
        settings.playsSound = false
        return (IslandPanelController(flow: flow, settings: settings), settings)
    }

    private func assertBodyScrolls(in window: NSWindow) throws {
        let host = try XCTUnwrap(window.contentView)
        let scroll = try XCTUnwrap(descendants(of: host, type: NSScrollView.self).first)
        XCTAssertGreaterThan(scroll.documentView?.frame.height ?? 0, scroll.contentView.bounds.height)
        XCTAssertTrue(host.bounds.contains(host.convert(scroll.bounds, from: scroll)))
    }

    private func assertReplyIsVisible(in window: NSWindow) throws {
        let host = try XCTUnwrap(window.contentView)
        let field = try XCTUnwrap(descendants(of: host, type: NSTextField.self).first { $0.isEditable })
        XCTAssertTrue(host.bounds.contains(host.convert(field.bounds, from: field)))
    }

    private func descendants<T: NSView>(of view: NSView, type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            (child as? T).map { [$0] } ?? descendants(of: child, type: type)
        }
    }

    private func settle(_ window: NSWindow) async throws {
        try await Task.sleep(for: .seconds(AppConstants.Island.animationDuration + 0.2))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.layoutSubtreeIfNeeded()
    }
}

private struct SizingTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
