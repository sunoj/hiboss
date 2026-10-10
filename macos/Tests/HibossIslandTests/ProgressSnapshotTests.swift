// Hosts the actual Progress sidebar destination and native empty/error/loading surfaces.
// Exports: ProgressSnapshotTests; HIBOSS_SNAPSHOT_DIR saves light/dark PNG evidence.
// Dependencies: AppKit, SwiftUI, XCTest and synthetic loopback image/poster fixtures.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class ProgressSnapshotTests: XCTestCase {
    func testHostedSidebarProgressWithImageVideoAndTextInBothAppearances() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let posts = ProgressFixtures.posts(baseURL: server.baseURL)
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: posts)])
        api.projects = [ProgressProject(project: "hiboss", count: 2, lastPostAt: nil, agentId: "builder")]
        for scheme in [ColorScheme.light, .dark] {
            let panels = PanelsModel(demoMode: true, autoload: false)
            var mounted = false
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .progress, previewHistory: [], progressProvider: { api },
                panelsModel: panels)
                .environment(\.colorScheme, scheme).onAppear { mounted = true })
            host.sizingOptions = []
            let window = try await makeWindow(host, scheme: scheme)
            defer { window.close() }
            try await waitForCondition { mounted && !api.reads.isEmpty }
            XCTAssertEqual(posts.map(\.id), ["image", "video", "text"])
            XCTAssertEqual(posts[0].media.first?.kind, .image)
            XCTAssertEqual(posts[1].media.first?.kind, .video)
            XCTAssertTrue(posts[2].media.isEmpty)
            XCTAssertNil(panels.selectedTile)
            try await write(host, name: "progress-\(scheme == .light ? "light" : "dark")")
        }
    }

    func testHostedExplicitLoadingEmptyAndErrorStates() async throws {
        for state in ["loading", "empty", "error"] {
            let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: [])])
            api.holdsRead = state == "loading"
            api.failsRead = state == "error"
            let store = ProgressFeedStore { api }
            for scheme in [ColorScheme.light, .dark] {
                var mounted = false
                let host = NSHostingView(rootView: NavigationStack { ProgressWorkspace(store: store) }
                    .environment(\.colorScheme, scheme).onAppear { mounted = true })
                host.sizingOptions = []
                let window = try await makeWindow(host, scheme: scheme)
                defer { window.close() }
                try await waitForCondition {
                    mounted && (state == "loading" ? api.pendingRead != nil : store.didLoad)
                }
                XCTAssertEqual(store.isRefreshing, state == "loading")
                XCTAssertEqual(store.loadError != nil, state == "error")
                try await write(host, name: "progress-\(state)-\(scheme == .light ? "light" : "dark")")
                if state == "loading" {
                    api.releaseRead()
                    try await waitForCondition { !store.isRefreshing }
                    store.reset()
                }
            }
        }
    }

    func testPanelSelectionFromProgressStillOpensTodayInspector() async throws {
        let panels = PanelsModel(demoMode: true, autoload: false)
        let api = ScriptedProgressAPI()
        let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
            initialDestination: .progress, previewHistory: [], progressProvider: { api },
            panelsModel: panels))
        host.sizingOptions = []
        let window = try await makeWindow(host, scheme: .light)
        defer { window.close() }
        try await waitForCondition { !api.reads.isEmpty }
        let tile = try XCTUnwrap(panels.tiles.first)
        panels.open(tile.id)
        try await waitForCondition { window.title == L("Today") }
        XCTAssertEqual(panels.selectedTileID, tile.id)
        let snapshot = OverviewStore().snapshot
        let today = TodayView(snapshot: snapshot, reply: AttentionReplyState(), panels: panels,
            onChoose: { _, _ in nil }, onSession: { _ in })
        XCTAssertTrue(today.hasInspectorContent)
    }

    private func makeWindow(_ host: NSView, scheme: ColorScheme) async throws -> NSWindow {
        _ = NSApplication.shared
        // Mount the toolbar with spare screen space before expanding the hosted window.
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1160, height: 600),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitForCondition { window.toolbar != nil }
        try await Task.sleep(for: .milliseconds(250))
        let visible = try XCTUnwrap(window.screen?.visibleFrame)
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 1160, height: 1060))
        frame.size.height = min(frame.height, visible.height)
        frame.origin = NSPoint(x: visible.minX + 80, y: visible.maxY - frame.height)
        window.setFrame(frame, display: true)
        XCTAssertLessThanOrEqual(window.frame.height, visible.height)
        return window
    }

    private func bitmap(_ host: NSView) -> NSBitmapImageRep? {
        host.layoutSubtreeIfNeeded()
        host.window?.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        return bitmap
    }

    private func blueSamples(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 10) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 10) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent > 0.5, color.blueComponent > color.redComponent * 1.4 {
                    count += 1
                }
            }
        }
        return count
    }

    private func write(_ host: NSView, name: String) async throws {
        host.layoutSubtreeIfNeeded()
        host.window?.displayIfNeeded()
        // Keep the run loop responsive while the native compositor finishes its layers.
        try await Task.sleep(for: .milliseconds(750))
        if let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let window = try XCTUnwrap(host.window)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                url.appendingPathComponent("\(name).png").path]
            try capture.run()
            try await waitForCondition { !capture.isRunning }
            XCTAssertEqual(capture.terminationStatus, 0)
            if name == "progress-light" || name == "progress-dark" {
                let data = try Data(contentsOf: url.appendingPathComponent("\(name).png"))
                XCTAssertGreaterThan(blueSamples(in: try XCTUnwrap(NSBitmapImageRep(data: data))), 1_000,
                    "Both the image and video poster must finish rendering")
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(data: data).perform([request])
                let labels = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
                for label in ["Builder", "Designer", "Tester", "All projects"] {
                    XCTAssertTrue(labels.contains { $0.contains(label) },
                        "Post authors and the project picker must remain readable: \(label)")
                }
            }
        }
        let bitmap = try XCTUnwrap(bitmap(host))
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 1160)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, 1060)
    }
}
