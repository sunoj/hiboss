// Exercises unread indicators through the hosted MainView and native sidebar selection.
// Exports: SessionUnreadWindowTests with key-window arrival and light/dark capture evidence.
// Dependencies: AppKit, SwiftUI, XCTest, HibossKit, and existing window capture helpers.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class SessionUnreadWindowTests: XCTestCase {
    private let now = Date.now
    private let account = SessionReadAccount(config: ConnectionConfig(
        serverURL: URL(string: "https://unread.invalid")!, bossToken: "synthetic-unread-account"))

    func testSelectingSessionClearsUnreadAndKeyWindowArrivalsStayRead() async throws {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let window = try await show(fixture, scheme: .light)
        defer { window.close() }
        try await waitForCondition { self.visible("sidebar.unread.unread", fixture.probe) }
        XCTAssertTrue(fixture.reads.unreadSessionIDs(in: fixture.overview.snapshot).contains("unread"))
        let label = try XCTUnwrap(fixture.probe.anchors["sidebar.label.unread"])
        let before = label.convert(label.bounds, to: nil)
        try await select("unread", fixture: fixture, window: window)
        try await waitForCondition {
            fixture.reads.lastRead["unread"] != nil
                && !self.visible("sidebar.unread.unread", fixture.probe)
        }
        XCTAssertTrue(fixture.focus.isKey)
        let incoming = message("arrival", session: "unread", at: 10)
        update(fixture, adding: incoming)
        try await waitForCondition {
            fixture.reads.lastRead["unread"]! >= HistoryTimestamp.date(from: incoming.createdAt)!
        }
        try await BoxWindowCaptureSupport.settle(window)
        XCTAssertFalse(visible("sidebar.unread.unread", fixture.probe))
        XCTAssertFalse(fixture.reads.unreadSessionIDs(in: fixture.overview.snapshot).contains("unread"))
        let after = label.convert(label.bounds, to: nil)
        XCTAssertEqual(before.minX, after.minX, accuracy: 0.1)
        XCTAssertEqual(before.height, after.height, accuracy: 0.1)
    }

    func testSelectedSessionInNonKeyWindowBecomesUnreadUntilWindowReturns() async throws {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let window = try await show(fixture, scheme: .light)
        defer { window.close() }
        try await select("unread", fixture: fixture, window: window)
        try await waitForCondition { fixture.reads.lastRead["unread"] != nil }
        fixture.focus.isKey = false
        try await BoxWindowCaptureSupport.settle(window)
        XCTAssertFalse(fixture.focus.isKey)
        update(fixture, adding: message("background", session: "unread", at: 20))
        try await waitForCondition { self.visible("sidebar.unread.unread", fixture.probe) }
        fixture.focus.isKey = true
        try await waitForCondition { !self.visible("sidebar.unread.unread", fixture.probe) }
        XCTAssertFalse(fixture.reads.unreadSessionIDs(in: fixture.overview.snapshot).contains("unread"))
    }

    func testLightAndDarkWorkingReadNeedsYouUnreadAndIdleRowsKeepTheirGeometry() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let fixture = makeFixture()
            defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
            let window = try await show(fixture, scheme: scheme)
            defer { window.close() }
            XCTAssertTrue(visible("sidebar.unread.unread", fixture.probe))
            XCTAssertTrue(visible("sidebar.needsYou.needs-you", fixture.probe))
            XCTAssertFalse(visible("sidebar.unread.needs-you", fixture.probe))
            XCTAssertTrue(visible("sidebar.working.working", fixture.probe))
            XCTAssertFalse(visible("sidebar.unread.working", fixture.probe))
            XCTAssertFalse(visible("sidebar.unread.idle", fixture.probe))
            try assertGeometry(fixture)
            let directory = ProcessInfo.processInfo.environment["HIBOSS_UNREAD_SNAPSHOTS"]
                ?? "/private/tmp/hiboss-session-unread-screenshots"
            try BoxWindowCaptureSupport.capture(window, directory: directory,
                name: "session-unread-\(scheme == .light ? "light" : "dark")")
        }
    }

    func testAccountSwitchUsesFreshBaselineAndRestoresOriginalSessionReads() async throws {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let window = try await show(fixture, scheme: .light)
        defer { window.close() }
        try await select("unread", fixture: fixture, window: window)
        try await waitForCondition { fixture.reads.lastRead["unread"] != nil }
        let previousRead = fixture.reads.lastRead["unread"]
        let previousConfig = try XCTUnwrap(fixture.settings.activeClientConfig)
        let next = try fixture.settings.activateDeviceToken("synthetic-second-account", replacing: previousConfig)
        try await waitForCondition { fixture.reads.baseline > self.now.addingTimeInterval(-1) }
        XCTAssertTrue(fixture.reads.lastRead.isEmpty)
        _ = try fixture.settings.activateDeviceToken(previousConfig.bossToken, replacing: next)
        try await waitForCondition { fixture.reads.lastRead["unread"] == previousRead }
        XCTAssertEqual(fixture.reads.baseline, now.addingTimeInterval(-120))
    }

    @MainActor private struct Fixture {
        let defaults: UserDefaults
        let name: String
        let reads: SessionReadStore
        let overview: OverviewStore
        let settings: AppSettings
        let probe = LayoutProbe()
        let focus = UnreadWindowFocus()
    }

    private func makeFixture() -> Fixture {
        let name = "SessionUnreadWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let reads = SessionReadStore(defaults: defaults)
        reads.activate(account, now: now.addingTimeInterval(-120))
        let history = [message("unread", session: "unread", at: -10),
            message("needs-you", session: "needs-you", at: -20, options: ["Review"]),
            message("working", session: "working", at: -30, status: "working"),
            message("idle", session: "idle", at: -10800)]
        reads.markRead("working", messages: history, now: now)
        let overview = OverviewStore(identity: AccountAuthorization())
        overview.update(history: history, live: nil, now: now, health: .live(checkedAt: now),
            coverageComplete: true, requiredInputs: history.filter(\.isDecision), requiredInputLoaded: true)
        let settings = AppSettings(defaults: defaults, keychain: UnreadTokens())
        settings.serverAddress = account.serverURL.absoluteString
        return Fixture(defaults: defaults, name: name, reads: reads, overview: overview, settings: settings)
    }

    private func show(_ fixture: Fixture, scheme: ColorScheme) async throws -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let settings = fixture.settings
        await settings.loadToken()
        let flow = OptionFlowStore()
        let panels = PanelsModel(demoMode: true, autoload: false)
        let host = NSHostingView(rootView: UnreadHostedWorkspace(focus: fixture.focus) { isKey in
            MainView(settings: settings, flow: flow,
                overviewStore: fixture.overview, previewHistory: nil, panelsModel: panels,
                sessionReadStore: fixture.reads, sessionWindowIsKey: isKey)
        }
            .environment(\.colorScheme, scheme).environment(\.layoutProbe, fixture.probe))
        host.sizingOptions = []
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let size = NSSize(width: min(1160, screen.width - 40), height: min(700, screen.height - 100))
        let window = NSWindow(contentRect: NSRect(origin: screen.origin, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitForCondition { self.visible("sidebar.session.idle", fixture.probe) }
        try await BoxWindowCaptureSupport.settle(window)
        return window
    }

    private func select(_ id: String, fixture: Fixture, window: NSWindow) async throws {
        let anchor = try XCTUnwrap(fixture.probe.anchors["sidebar.session.\(id)"])
        let root = try XCTUnwrap(window.contentView)
        let table = try XCTUnwrap(BoxWindowCaptureSupport.descendants(root).compactMap {
            $0 as? NSTableView
        }.first { anchor.isDescendant(of: $0) })
        let point = anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY), to: table)
        let index = table.row(at: point)
        XCTAssertGreaterThanOrEqual(index, 0)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                continuation.resume()
            }
        }
        window.makeFirstResponder(table)
    }

    private func update(_ fixture: Fixture, adding message: HistoryMessage) {
        let snapshot = fixture.overview.snapshot
        fixture.overview.update(history: snapshot.history + [message], live: nil,
            health: .live(checkedAt: now), coverageComplete: true,
            requiredInputs: snapshot.attention.map(\.message), requiredInputLoaded: true)
    }

    private func visible(_ id: String, _ probe: LayoutProbe) -> Bool {
        probe.anchors[id]?.window != nil
    }

    private func assertGeometry(_ fixture: Fixture) throws {
        let probe = fixture.probe
        let caption = try XCTUnwrap(probe.anchors["sidebar.working.working"])
        let agent = try XCTUnwrap(probe.anchors["sidebar.agent.working"])
        let row = try XCTUnwrap(probe.anchors["sidebar.session.working"])
        let ideal = NSHostingView(rootView: Text(L("Working")).font(.caption)).fittingSize.width
        XCTAssertGreaterThanOrEqual(caption.bounds.width, ideal - 1)
        XCTAssertTrue(row.bounds.contains(caption.convert(caption.bounds, to: row)))
        XCTAssertLessThanOrEqual(agent.convert(agent.bounds, to: row).maxX,
            caption.convert(caption.bounds, to: row).minX)
        for id in ["unread", "needs-you", "idle"] {
            let slot = try XCTUnwrap(probe.anchors["sidebar.dotSlot.\(id)"])
            XCTAssertEqual(slot.bounds.width, 7, accuracy: 0.1)
        }
    }

    private func message(_ id: String, session: String, at seconds: TimeInterval,
                         options: [String] = [], status: String = "idle") -> HistoryMessage {
        HistoryMessage(id: MessageID(rawValue: id), body: "Session update", agentName: "Long Agent Name",
            direction: "agent_to_boss", status: "delivered", priority: "normal",
            metadata: MessageMetadata(options: options),
            createdAt: AttentionTestSupport.iso(now.addingTimeInterval(seconds)),
            sessionId: session, sessionLabel: session, sessionStatus: status)
    }
}

private struct UnreadTokens: TokenStoring {
    func read() throws -> String? { "synthetic-unread-account" }
    func write(_ token: String) throws {}
    func delete() throws {}
}

@MainActor
private final class UnreadWindowFocus: ObservableObject {
    @Published var isKey = true
}

private struct UnreadHostedWorkspace: View {
    @ObservedObject var focus: UnreadWindowFocus
    let workspace: (Binding<Bool>) -> MainView

    var body: some View { workspace($focus.isKey) }
}
