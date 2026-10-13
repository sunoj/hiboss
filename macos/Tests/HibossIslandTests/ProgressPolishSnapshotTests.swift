// Captures full Progress windows and asserts centred content and a single enabled error retry.
// Exports: ProgressPolishSnapshotTests with light/dark loaded, error, menu and viewer evidence.
// Dependencies: AppKit, SwiftUI, Vision, XCTest and loopback progress image fixtures.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class ProgressPolishSnapshotTests: XCTestCase {
    func testLoadedFeedAndErrorFillDetailInBothAppearances() async throws {
        let server = ProgressPolishMediaServer()
        try await server.start()
        defer { server.stop() }
        for scheme in [ColorScheme.light, .dark] {
            for failed in [false, true] {
                let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: posts(server.baseURL))])
                api.failsRead = failed
                api.projects = [ProgressProject(project: "hiboss", count: 2, lastPostAt: nil,
                    agentId: "fixture")]
                let store = ProgressFeedStore { api }
                let identity = ProjectIdentity(id: "canonical", slug: "hiboss", displayName: "HiBoss",
                    avatarURL: URL(string: server.baseURL + "/square.png"))
                let session = ProjectSession(id: "hiboss", projectId: identity.id,
                    projectSlug: identity.slug, branch: "main", projectRef: identity)
                let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                    initialDestination: .progress,
                    previewHistory: PhaseBSnapshotFixtures.history(baseURL: server.baseURL),
                    previewSessions: [session],
                    progressStore: store, panelsModel: PanelsModel(demoMode: true, autoload: false))
                    .environment(\.colorScheme, scheme))
                host.sizingOptions = []
                let window = window(host, scheme: scheme)
                defer { window.close() }
                try await waitForCondition { store.didLoad && window.toolbar != nil }
                let name = "progress-polish-\(failed ? "error" : "feed")-\(label(scheme))"
                let data = try await capture(window, name: name)
                let observations = try recognize(data)
                if failed {
                    try await assertError(observations, window: window, api: api)
                } else {
                    try assertFeed(observations, window: window)
                }
            }
        }
    }

    func testCachedImageViewerInBothAppearances() async throws {
        let server = ProgressPolishMediaServer()
        try await server.start()
        defer { server.stop() }
        let address = server.baseURL + "/square.png"
        await ProgressImageLoader(url: address).load(address)
        let media = ProgressMedia(url: address, kind: .image, contentType: "image/png", size: 0,
            width: 400, height: 400)
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: ProgressMediaViewer(media: media))
            host.sizingOptions = []
            let window = window(host, scheme: scheme)
            defer { window.close() }
            let labels = try recognize(await capture(window, name: "progress-polish-viewer-\(label(scheme))"))
            XCTAssertFalse(labels.contains { $0.text.contains("Loading image") })
            XCTAssertTrue(labels.contains { $0.text.contains("Square avatar") })
            XCTAssertTrue(labels.contains { $0.text == "Close" })
        }
    }

    func testProjectFilterMenuInBothAppearances() async throws {
        let api = ScriptedProgressAPI()
        api.projects = [ProgressProject(project: "hiboss", count: 2, lastPostAt: nil, agentId: "fixture")]
        let store = ProgressFeedStore { api }
        await store.refresh()
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: NavigationStack { ProgressWorkspace(store: store) })
            host.sizingOptions = []
            let window = window(host, scheme: scheme)
            defer { window.close() }
            try await waitForCondition { window.toolbar != nil }
            try await waitForCondition { self.projectMenu(in: window) != nil }
            let menu = try XCTUnwrap(projectMenu(in: window))
            XCTAssertEqual(menu.items.map(\.title), ["All projects", "hiboss"])
            try captureOpenMenu(menu, in: host, name: "progress-polish-menu-\(label(scheme))")
        }
    }

    private func projectMenu(in window: NSWindow) -> NSMenu? {
        for item in window.toolbar?.items ?? [] {
            if let menu = item.menuFormRepresentation?.submenu { return menu }
        }
        let roots = [window.contentView].compactMap { $0 }
            + (window.toolbar?.items.compactMap(\.view) ?? [])
        let views = roots.flatMap { [$0] + descendants($0) }
        let menu = views.compactMap { ($0 as? NSPopUpButton)?.menu ?? ($0 as? NSButton)?.menu }.first
        return menu
    }

    private func captureOpenMenu(_ menu: NSMenu, in host: NSView, name: String) throws {
        let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("progress-polish").path
        let output = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let tracking = ProgressMenuTracking(menu: menu)
        let frame = try XCTUnwrap(host.window).frame
        let top = try XCTUnwrap(NSScreen.screens.first).frame.maxY
        let region = "\(Int(frame.minX)),\(Int(top - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
        let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
            MainActor.assumeIsolated {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-R", region, output.path]
                do {
                    try process.run()
                    process.waitUntilExit()
                    XCTAssertEqual(process.terminationStatus, 0)
                } catch { XCTFail("Menu capture failed: \(error)") }
                tracking.menu.cancelTracking()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        let position = NSPoint(x: host.bounds.maxX - 140, y: host.isFlipped ? 20 : host.bounds.maxY - 20)
        menu.popUp(positioning: nil, at: position, in: host)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    private func assertError(_ observations: [(text: String, bounds: CGRect)], window: NSWindow,
                             api: ScriptedProgressAPI) async throws {
        let error = try XCTUnwrap(observations.first { $0.text.contains("Progress unavailable") })
        XCTAssertEqual(error.bounds.midX, 0.59, accuracy: 0.07)
        XCTAssertEqual(error.bounds.midY, 0.5, accuracy: 0.12)
        XCTAssertEqual(observations.filter { $0.text == "Retry" }.count, 1)
        XCTAssertFalse(observations.contains { $0.text.contains("Update failed") })
        let retry = try XCTUnwrap(observations.first { $0.text == "Retry" })
        let reads = api.reads.count
        try click(retry.bounds, in: window)
        try await waitForCondition { api.reads.count > reads }
    }

    private func assertFeed(_ observations: [(text: String, bounds: CGRect)], window: NSWindow) throws {
        let marker = try XCTUnwrap(observations.first { $0.text.contains("Centred timeline") })
        XCTAssertGreaterThan(marker.bounds.minX, 0.21,
            "The readable column must be centred within the detail width")
        XCTAssertEqual(observations.filter { $0.text == "HiBoss" && $0.bounds.minX > 0.25 }.count, 2,
            "Both post headers must resolve the sidebar's display name")
        XCTAssertFalse(observations.contains { $0.text.contains("Loading image") })
        try assertTrailingFilterAndReadStatus(window)
    }

    func testImageGridGeometryDoesNotChangeWhenImagesLoad() async throws {
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let items = try XCTUnwrap(ProgressFixtures.posts(baseURL: server.baseURL).first?.media)
        var measured = CGSize.zero
        let host = NSHostingView(rootView: ProgressMediaGrid(items: items, onOpen: { _ in })
            .background(GeometryReader { geometry in
                Color.clear.onAppear { measured = geometry.size }
                    .onChange(of: geometry.size) { _, size in measured = size }
            }))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: 408, height: 200)
        let window = window(host, scheme: .light)
        defer { window.close() }
        try await waitForCondition { measured != .zero }
        let reserved = measured
        try await waitForCondition { server.requestedPaths.contains("/ship.png") }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(measured, reserved)
    }

    private func posts(_ base: String) -> [ProgressPost] {
        let media = [ProgressMedia(url: base + "/square.png", kind: .image, contentType: "image/png",
            size: 0, width: 400, height: 400),
            ProgressMedia(url: base + "/wide.png", kind: .image, contentType: "image/png",
                size: 0, width: 480, height: 320)]
        return [ProgressPost(id: "layout", project: "HIBOSS", agentId: "builder", agentName: "Builder",
            body: "Centred timeline with complete images.", media: media, createdAt: "2026-10-13T05:00:00Z"),
            ProgressPost(id: "second", project: "hiboss", agentId: "designer", agentName: "Designer",
                body: "Project avatars match the sidebar.", createdAt: "2026-10-13T05:00:00Z")]
    }

    private func assertTrailingFilterAndReadStatus(_ window: NSWindow) throws {
        let items = window.toolbar?.items.compactMap(\.view) ?? []
        let groups = items.filter { $0.bounds.width > 50 }
        XCTAssertFalse(groups.isEmpty)
        for view in groups {
            let rect = view.convert(view.bounds, to: nil)
            XCTAssertGreaterThan(rect.minX, window.frame.width * 0.7,
                "Toolbar group \(type(of: view)) must sit at the trailing edge: \(rect)")
        }
    }

    private func window(_ host: NSView, scheme: ColorScheme) -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 80, width: 1320, height: 760),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func click(_ bounds: CGRect, in window: NSWindow) throws {
        let location = NSPoint(x: bounds.midX * window.frame.width, y: bounds.midY * window.frame.height)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    private func label(_ scheme: ColorScheme) -> String { scheme == .light ? "light" : "dark" }

    private func capture(_ window: NSWindow, name: String) async throws -> Data {
        try await Task.sleep(for: .milliseconds(750))
        let directory = ProcessInfo.processInfo.environment["HIBOSS_SNAPSHOT_DIR"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("progress-polish").path
        let output = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.path]
        try process.run()
        try await waitForCondition { !process.isRunning }
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: output)
    }

    private func recognize(_ data: Data) throws -> [(text: String, bounds: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(data: data).perform([request])
        return request.results?.compactMap { result in
            result.topCandidates(1).first.map { ($0.string, result.boundingBox) }
        } ?? []
    }
}

@MainActor
private final class ProgressMenuTracking {
    let menu: NSMenu

    init(menu: NSMenu) { self.menu = menu }
}
