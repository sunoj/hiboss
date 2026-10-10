// Hosts session composers at compact sizes and exercises the native send control.
// Exports: SessionLayoutTests for disabled empty sessions, retry drafts, and reachable editors.
// Dependencies: AppKit, SwiftUI, XCTest, and the production SessionComposer.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class SessionLayoutTests: XCTestCase {
    func testNoAgentMessageDisablesTheNativeReplyFieldInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: SessionComposer(context: context([]),
                reply: AttentionReplyState(),
                onChoose: { _, _ in
                    XCTFail("An empty session cannot send")
                    return nil
                })
                .environment(\.colorScheme, scheme))
            let window = show(host, size: NSSize(width: 360, height: 180), scheme: scheme)
            defer { window.close() }
            try await waitForCondition { !self.fields(host).isEmpty }
            XCTAssertTrue(fields(host).allSatisfy { !$0.isEnabled })
        }
    }

    func testSavedSessionDraftFitsShortWindowsAndKeyboardSendKeepsItsTarget() async throws {
        let reply = AttentionReplyState()
        let message = HistoryMessage.fixture(id: "target", body: "Delivered result")
        reply.drafts[message.id] = "Please review the result before shipping."
        var receipts: [RecordedReply] = []
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: SessionComposer(context: context([message]), reply: reply,
                onChoose: { text, id in
                    receipts.append(RecordedReply(messageID: id, choice: text))
                    return nil
                })
                .environment(\.colorScheme, scheme))
            let window = show(host, size: NSSize(width: 360, height: 220), scheme: scheme)
            defer { window.close() }
            try await waitForCondition { !self.fields(host).isEmpty }
            for field in fields(host) {
                XCTAssertTrue(field.isEnabled)
                XCTAssertTrue(host.bounds.contains(field.convert(field.bounds, to: host)))
            }
            try await sendShortcut(window)
            try await waitForCondition { reply.drafts[message.id] == nil }
            XCTAssertEqual(receipts.last?.messageID, "target")
            reply.drafts[message.id] = "Please review the result before shipping."
        }
        XCTAssertEqual(receipts.count, 2)
    }

    func testSessionWorkspaceComposerFitsCompactAndWideNavigation() async throws {
        let message = HistoryMessage(id: "target", body: "Delivered result", agentName: "Agent",
            direction: "agent_to_boss", status: "delivered", priority: "normal",
            createdAt: AttentionTestSupport.iso(.now), sessionId: "session")
        for width: CGFloat in [480, 760, 1320] {
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .session("session"), previewHistory: [message],
                panelsModel: PanelsModel(demoMode: false, autoload: false)))
            let window = show(host, size: NSSize(width: width, height: 480), scheme: .light)
            defer { window.close() }
            try await waitForCondition { !self.fields(host).isEmpty }
            host.layoutSubtreeIfNeeded()
            let editors = fields(host).filter(\.isEnabled)
            XCTAssertFalse(editors.isEmpty)
            for editor in editors {
                XCTAssertGreaterThan(editor.bounds.width, 100)
                XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1)
                    .contains(editor.convert(editor.bounds, to: host)))
            }
        }
    }

    func testTextOnlyBlockingDecisionCanSendItsSavedCustomReplyInPlace() async throws {
        let message = HistoryMessage(id: "text", body: "Describe the rollback plan", agentName: "Agent",
            direction: "agent_to_boss", status: "delivered", priority: "normal", mode: "blocking",
            createdAt: AttentionTestSupport.iso(.now), sessionId: "session")
        let item = try XCTUnwrap(AttentionModel.items(from: [message], now: .now).first)
        let reply = AttentionReplyState()
        reply.drafts[message.id] = "Keep a database backup"
        var received: String?
        let host = NSHostingView(rootView: HistoryThreadRow(thread: MessageThread(message: message),
            decision: item, usesV4: true,
            answerability: AnswerableDecisions(isLoaded: true, openIDs: [message.id]), reply: reply,
            isExpanded: .constant(true), isSearching: false,
            onCollapse: {}, onChoose: { received = $0; return nil }).padding(20))
        let window = show(host, size: NSSize(width: 600, height: 450), scheme: .light)
        defer { window.close() }
        try await waitForCondition { !self.fields(host).isEmpty }
        let editor = try XCTUnwrap(fields(host).first)
        XCTAssertTrue(window.makeFirstResponder(editor))
        try await waitForCondition { editor.currentEditor() != nil }
        try await sendShortcut(window)
        try await waitForCondition { received != nil }
        XCTAssertEqual(received, "Keep a database backup")
        XCTAssertEqual(reply.drafts[message.id] ?? "", "")
    }

    private func fields(_ host: NSView) -> [NSTextField] {
        host.subviews.flatMap { view in
            (view as? NSTextField).map { [$0] } ?? fields(view)
        }.filter(\.isEditable)
    }

    private func context(_ history: [HistoryMessage]) -> SessionContext {
        let id = history.first.map { SessionGrouping.sessionKey(for: $0) } ?? "session"
        return SessionContext(id: id,
            snapshot: OverviewSnapshot(history: history, live: nil, now: .now, requiredInputLoaded: true),
            inventory: [])
    }

    private func sendShortcut(_ window: NSWindow) async throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        try await waitForCondition { window.performKeyEquivalent(with: event) }
    }

    private func show(_ host: NSView, size: NSSize, scheme: ColorScheme) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
