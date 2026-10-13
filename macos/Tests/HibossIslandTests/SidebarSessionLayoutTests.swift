// Measures long sidebar labels, untruncated nicknames, and unchanged two-line row heights.
// Exports: SidebarSessionLayoutTests; HIBOSS_V4_SNAPSHOTS captures long-name window evidence.
// Dependencies: AppKit, SwiftUI, XCTest, HibossKit, and production sidebar layout probes.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class SidebarSessionLayoutTests: XCTestCase {
    private let longLabel = "house/codex/site-retained-vegetation"
    private let fullAgent = "ming-claude@Mings-Mac-Mini"

    func testLabelsAndAgentsKeepFullDescriptionWhileShorteningVisibleNames() throws {
        let snapshot = snapshot()
        let session = try XCTUnwrap(snapshot.today.sessionDirectory.working.first { $0.id == "long" })
        let text = SidebarSessionText(session: session, facts: inventory[0])
        XCTAssertEqual(text.label, longLabel)
        XCTAssertEqual(text.nickname, " · squid")
        XCTAssertEqual(text.agent, "ming-claude")
        XCTAssertEqual(text.fullDescription, longLabel + " · squid · " + fullAgent)
        let fallback = SidebarSessionText(session: session, facts: nil)
        XCTAssertNil(fallback.nickname)
        XCTAssertEqual(fallback.label, session.projectLabel)
        XCTAssertTrue(fallback.fullDescription.contains(fullAgent))
    }

    func testLongLabelReservesWholeNicknameAndKeepsRowHeightInBothAppearances() async throws {
        _ = NSApplication.shared
        for scheme in [ColorScheme.light, .dark] {
            for width in [220.0, 300.0] {
                let probe = LayoutProbe()
                let sidebar = OverviewSidebar(snapshot: snapshot(), selection: .session("long"),
                    historyState: .loaded, connectionState: .connected,
                    onSelect: { _ in }, onSettings: {}, onRefresh: {})
                    .environment(\.projectSessions, inventory).environment(\.colorScheme, scheme)
                    .environment(\.layoutProbe, probe)
                let host = NSHostingView(rootView: sidebar)
                let window = show(host, width: width, scheme: scheme)
                defer { window.close() }
                try await waitForCondition { probe.anchors["sidebar.session.long"]?.window != nil }
                host.layoutSubtreeIfNeeded()
                try assertLayout(probe)
                let appearance = scheme == .light ? "light" : "dark"
                try await capture(window, name: "sidebar-long-\(Int(width))-\(appearance)")
            }
        }
    }

    private func assertLayout(_ probe: LayoutProbe) throws {
        let label = try XCTUnwrap(probe.anchors["sidebar.label.long"])
        let nickname = try XCTUnwrap(probe.anchors["sidebar.nickname.long"])
        let row = try XCTUnwrap(probe.anchors["sidebar.session.long"])
        let shortRow = try XCTUnwrap(probe.anchors["sidebar.session.short"])
        let idealNickname = NSHostingView(rootView: Text(verbatim: " · squid")).fittingSize.width
        let idealLabel = NSHostingView(rootView: Text(verbatim: longLabel)).fittingSize.width
        XCTAssertGreaterThanOrEqual(nickname.bounds.width, idealNickname - 1)
        XCTAssertLessThan(label.bounds.width, idealLabel, "The long label must yield space to the nickname")
        let labelFrame = label.convert(label.bounds, to: row)
        let nicknameFrame = nickname.convert(nickname.bounds, to: row)
        XCTAssertLessThanOrEqual(labelFrame.maxX, nicknameFrame.minX + 1)
        XCTAssertTrue(row.bounds.insetBy(dx: -1, dy: -1).contains(nicknameFrame))
        XCTAssertEqual(row.bounds.height, shortRow.bounds.height, accuracy: 1)
    }

    private var inventory: [ProjectSession] {
        [ProjectSession(id: "long", projectId: nil, projectSlug: "house",
            branch: "codex/site-retained-vegetation", label: longLabel,
            agentName: fullAgent, nickname: "squid"),
         ProjectSession(id: "short", projectId: nil, projectSlug: "hiboss", branch: "main",
            agentName: fullAgent, nickname: "conch")]
    }

    private func snapshot() -> OverviewSnapshot {
        let history = inventory.map { session in
            HistoryMessage(id: MessageID(rawValue: session.id), body: "Working on the session.",
                agentName: fullAgent, direction: "agent_to_boss", status: "delivered", priority: "normal",
                createdAt: AttentionTestSupport.iso(.now), sessionId: session.id,
                sessionLabel: session.displayLabel, sessionStatus: "working")
        }
        return OverviewSnapshot(history: history, live: nil, now: .now, requiredInputLoaded: true)
    }

    private func show<Content: View>(_ host: NSHostingView<Content>, width: Double,
                                    scheme: ColorScheme) -> NSWindow {
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: width, height: 780),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func capture(_ window: NSWindow, name: String) async throws {
        guard let path = ProcessInfo.processInfo.environment["HIBOSS_V4_SNAPSHOTS"] else { return }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        window.displayIfNeeded()
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), "\(path)/\(name).png"]
        try capture.run()
        try await waitForCondition { !capture.isRunning }
        XCTAssertEqual(capture.terminationStatus, 0)
    }
}
