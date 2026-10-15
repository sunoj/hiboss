// Full-window session thread captures with a decision, reply, follow-up and merged updates.
// Exports: SessionThreadWindowTests; screenshots live outside the source checkout.
// Dependencies: AppKit, SwiftUI, XCTest, production MainView and window capture support.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class SessionThreadWindowTests: XCTestCase {
    func testSessionThreadsInLightAndDark() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let history = fixtures()
        let folded = MessageThread.fold(history)
        XCTAssertEqual(folded.first { $0.id == "answered" }?.entries.count, 2)
        XCTAssertEqual(SessionThreadLogic.reactionChips(history[3]).first?.text, "👍 2")
        // SessionThreadEntries renders all members; the real workspace supplies chrome and Watching.
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .session("thread-demo"), previewHistory: history,
                panelsModel: PanelsModel(demoMode: false, autoload: false))
                .environment(\.colorScheme, scheme))
            host.sizingOptions = []
            let window = show(host, scheme: scheme)
            defer { window.close() }
            try await waitForCondition { window.toolbar != nil }
            try await BoxWindowCaptureSupport.settle(window)
            let directory = "/private/tmp/hiboss-thread-ui-screenshots"
            try BoxWindowCaptureSupport.capture(window, directory: directory,
                name: "session-threads-\(scheme == .light ? "light" : "dark")")
            XCTAssertGreaterThan(host.bounds.width, 600)
        }
    }

    private func show(_ host: NSView, scheme: ColorScheme) -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1280, screen.width - 40), height: min(1000, screen.height - 80))
        let window = NSWindow(contentRect: NSRect(origin: screen.origin, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func fixtures() -> [HistoryMessage] {
        let now = Date.now
        func message(_ id: String, _ body: String, _ minutes: Double,
                     parent: String? = nil, boss: Bool = false,
                     metadata: MessageMetadata? = nil) -> HistoryMessage {
            HistoryMessage(id: MessageID(rawValue: id), body: body, agentName: "Build Agent",
                direction: boss ? "boss_to_agent" : "agent_to_boss", status: "delivered", priority: "normal",
                replyTo: parent, metadata: metadata,
                expiresAt: id == "open" ? AttentionTestSupport.iso(now.addingTimeInterval(3600)) : nil,
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-minutes * 60)),
                sessionId: "thread-demo", sessionLabel: "Thread preview")
        }
        let reactions = MessageMetadata(options: [], reactions: [
            MessageReaction(emoji: "👍", actor: .boss, actorID: "one",
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-60))),
            MessageReaction(emoji: "👍", actor: .agent, actorID: "two",
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-50)))
        ])
        return [
            message("open", "Which validation should run next?", 4,
                metadata: MessageMetadata(options: ["Focused checks", "Full validation"],
                    defaultOption: "Focused checks")),
            message("answered", "The migration is ready. Continue with the review?", 30,
                metadata: MessageMetadata(options: ["Review", "Wait"])),
            message("reply", "Review", 25, parent: "answered", boss: true),
            message("follow", "Review complete. All focused checks passed.", 2,
                parent: "reply", metadata: reactions),
            message("update-1", "Indexed the changed files.", 20),
            message("update-2", "Validated the message models.", 15),
            message("update-3", "Prepared the review summary.", 10)
        ]
    }
}
