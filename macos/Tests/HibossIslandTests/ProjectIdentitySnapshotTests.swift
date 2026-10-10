// Hosts sidebar and session inspector with recent peers in both native appearances.
// Exports: ProjectIdentitySnapshotTests; HIBOSS_SNAPSHOT_DIR writes reviewable PNGs.
// Dependencies: AppKit, SwiftUI, HibossKit, production views, and synthetic Box fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class ProjectIdentitySnapshotTests: XCTestCase {
    func testSidebarAndSessionInspectorWithRecentPeersInLightAndDark() async throws {
        let history = messages()
        let snapshot = OverviewSnapshot(history: history, live: nil, now: .now,
            requiredInputs: history, requiredInputLoaded: true)
        let context = SessionContext(id: "self", snapshot: snapshot, inventory: inventory)
        XCTAssertEqual(context.peers.count, 7)
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: [])])
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            let sidebar = OverviewSidebar(snapshot: snapshot, selection: .session("self"),
                historyState: .loaded, connectionState: .connected,
                onSelect: { _ in }, onSettings: {}, onRefresh: {})
                .environment(\.projectSessions, inventory)
            try await capture(sidebar, size: NSSize(width: 300, height: 780),
                scheme: scheme, name: "project-sidebar-\(name)")
            let main = MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .session("self"), previewHistory: history, previewSessions: inventory,
                boxProvider: { api }, panelsModel: PanelsModel(demoMode: false, autoload: false))
            try await capture(main, size: NSSize(width: 1320, height: 880),
                scheme: scheme, name: "project-session-peers-\(name)")
        }
    }

    private var inventory: [ProjectSession] {
        let project = ProjectIdentity(id: "project", slug: "hiboss", displayName: "HiBoss")
        let main = ProjectSession(id: "self", projectId: "project", projectSlug: "hiboss", branch: "main",
            projectRef: project, host: "Mac mini", agentName: "Builder", status: "working",
            lastSeenAt: AttentionTestSupport.iso(.now), nickname: "otter")
        return [main] + (1...7).map { index in
            ProjectSession(id: "peer-\(index)", projectId: "project", projectSlug: "hiboss", branch: "main",
                projectRef: project, agentName: "Test Agent", status: "working",
                lastSeenAt: AttentionTestSupport.iso(Date.now.addingTimeInterval(-Double(index * 60))),
                nickname: ["fox", "palm", "coral", "finch", "cedar", "owl", "moss"][index - 1])
        }
    }

    private func messages() -> [HistoryMessage] {
        inventory.map { session in
            HistoryMessage(id: MessageID(rawValue: session.id),
                body: "Checking the project avatar and peers.",
                agentName: session.agentName, direction: "agent_to_boss", status: "delivered",
                priority: "normal", createdAt: session.lastSeenAt ?? "",
                sessionId: session.id,
                sessionLabel: "hiboss", sessionBranch: "main", sessionStatus: "working")
        }
    }

    private func capture<Content: View>(_ content: Content, size: NSSize,
                                       scheme: ColorScheme, name: String) async throws {
        _ = NSApplication.shared
        var mounted = false
        let host = NSHostingView(rootView: content.environment(\.colorScheme, scheme)
            .onAppear { mounted = true })
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await waitForCondition { mounted && !host.subviews.isEmpty }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(size.width))
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
        try await captureWindow(window, to: url.appendingPathComponent("\(name)-window.png"))
    }
    private func captureWindow(_ window: NSWindow, to url: URL) async throws {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try capture.run()
        try await waitForCondition { !capture.isRunning }
        XCTAssertEqual(capture.terminationStatus, 0)
    }
}
