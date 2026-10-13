// Captures relative timestamps in complete session, Box and Progress windows.
// Exports: RelativeTimestampCaptureTests with light/dark compositor and OCR assertions.
// Dependencies: AppKit, SwiftUI, Vision, production MainView and synthetic API fixtures.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class RelativeTimestampCaptureTests: XCTestCase {
    private var now = Date.now
    private let directory = ProcessInfo.processInfo.environment["HIBOSS_RELATIVE_SHOTS"]
        ?? "/private/tmp/hiboss-relative-shots"

    func testSessionTimelineShowsRelativeTimesInBothAppearances() async throws {
        now = .now
        for scheme in [ColorScheme.light, .dark] {
            let probe = LayoutProbe()
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .session("relative"), previewHistory: history,
                previewSessions: [ProjectSession(id: "relative", projectId: "project",
                    projectSlug: "HiBoss", branch: "timestamps", host: "Mac", agentName: "Builder",
                    status: "working", startedAt: timestamp(37500), lastSeenAt: timestamp(20))],
                boxProvider: { ScriptedBoxBrowser(pages: [BoxPage(items: [])]) },
                panelsModel: PanelsModel(demoMode: true, autoload: false))
                .environment(\.colorScheme, scheme).environment(\.layoutProbe, probe))
            host.sizingOptions = []
            let window = try await show(host, scheme: scheme)
            defer { window.close() }
            try await waitForCondition { probe.anchors["session.title"]?.window != nil }
            try await capture(window, surface: "session", scheme: scheme)
        }
    }

    func testBoxListAndAddedShowRelativeTimesInBothAppearances() async throws {
        now = .now
        let items = [BoxBrowserFixtures.item("recent", text: "Timestamp reference",
            createdAt: timestamp(37500)),
            BoxBrowserFixtures.item("minutes", text: "Recent note", createdAt: timestamp(1500))]
        let api = ScriptedBoxBrowser(pages: [BoxPage(items: items)])
        let store = BoxBrowserStore { api }
        let media = BoxBrowserMedia { api }
        defer { media.reset() }
        await store.refresh()
        store.selection = items[0].id
        for scheme in [ColorScheme.light, .dark] {
            let window = try await BoxWindowCaptureSupport.show(store: store, media: media,
                scheme: scheme, probe: LayoutProbe())
            defer { window.close() }
            try await capture(window, surface: "box", scheme: scheme)
        }
    }

    func testProgressFeedShowsRelativeTimesInBothAppearances() async throws {
        now = .now
        let posts = [ProgressPost(id: "hours", project: "hiboss", agentId: "builder",
            agentName: "Builder", body: "The shared timestamp format is ready.",
            createdAt: timestamp(37500)),
            ProgressPost(id: "minutes", project: "hiboss", agentId: "tester", agentName: "Tester",
                body: "Calendar and boundary checks passed.", createdAt: timestamp(1500))]
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: posts)])
        let store = ProgressFeedStore { api }
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .progress, previewHistory: [], progressProvider: { api },
                progressStore: store, panelsModel: PanelsModel(demoMode: true, autoload: false))
                .environment(\.colorScheme, scheme))
            host.sizingOptions = []
            let window = try await show(host, scheme: scheme)
            defer { window.close() }
            try await waitForCondition { store.didLoad && store.posts.count == posts.count }
            try await capture(window, surface: "progress", scheme: scheme)
        }
    }

    func testProgressMinuteTickKeepsTimestampAndAuthorPositions() async throws {
        let date = Date.now.addingTimeInterval(-(59 * 60 + 10))
        let post = ProgressPost(id: "tick", project: "hiboss", agentId: "builder", agentName: "Builder",
            body: "The timestamp updates while this post remains visible.",
            createdAt: AttentionTestSupport.iso(date))
        let api = ScriptedProgressAPI(pages: [ProgressFeedPage(posts: [post])])
        let store = ProgressFeedStore { api }
        let probe = LayoutProbe()
        let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
            initialDestination: .progress, previewHistory: [], progressProvider: { api },
            progressStore: store, panelsModel: PanelsModel(demoMode: true, autoload: false))
            .environment(\.colorScheme, .light).environment(\.layoutProbe, probe))
        host.sizingOptions = []
        let window = try await show(host, scheme: .light)
        defer { window.close() }
        try await waitForCondition { probe.anchors["progress.timestamp.tick"]?.window != nil }
        let anchor = try XCTUnwrap(probe.anchors["progress.timestamp.tick"])
        let initialFrame = anchor.convert(anchor.bounds, to: nil)
        let before = try recognize(window, name: "progress-tick-before")
        let initialText = SharedTimestamp.string(date)
        XCTAssertTrue(before.contains { $0.text == initialText })
        let author = try XCTUnwrap(before.first { $0.text == "Builder" })
        let deadline = ContinuousClock.now.advanced(by: .seconds(61))
        try await waitForCondition(timeout: .seconds(65)) { ContinuousClock.now >= deadline }
        let after = try recognize(window, name: "progress-tick-after")
        XCTAssertTrue(after.contains { $0.text == SharedTimestamp.string(date) })
        XCTAssertFalse(after.contains { $0.text == initialText })
        let updatedFrame = anchor.convert(anchor.bounds, to: nil)
        XCTAssertEqual(initialFrame.width, updatedFrame.width, accuracy: 0.5)
        XCTAssertEqual(initialFrame.maxX, updatedFrame.maxX, accuracy: 0.5)
        let updatedAuthor = try XCTUnwrap(after.first { $0.text == "Builder" })
        XCTAssertEqual(author.frame.minX, updatedAuthor.frame.minX, accuracy: 0.002)
        XCTAssertEqual(author.frame.minY, updatedAuthor.frame.minY, accuracy: 0.002)
    }

    private var history: [HistoryMessage] {
        [HistoryMessage(id: "question", body: "Keep the shared timestamp format?", agentName: "Builder",
            direction: "agent_to_boss", status: "replied", priority: "normal",
            metadata: MessageMetadata(options: ["Keep", "Change"]), createdAt: timestamp(37500),
            sessionId: "relative", sessionLabel: "HiBoss", sessionBranch: "timestamps"),
            HistoryMessage(id: "reply", body: "Keep", agentName: "Builder", direction: "boss_to_agent",
                status: "sent", priority: "normal", replyTo: "question",
                metadata: MessageMetadata(options: [], source: "ios"), createdAt: timestamp(1500),
                targetSessionId: "relative"),
            HistoryMessage(id: "update", body: "The boundary checks are ready for review.",
                agentName: "Tester", direction: "agent_to_boss", status: "delivered", priority: "normal",
                createdAt: timestamp(20), sessionId: "relative", sessionLabel: "HiBoss")]
    }

    private func timestamp(_ age: TimeInterval) -> String {
        AttentionTestSupport.iso(now.addingTimeInterval(-age))
    }

    private func show(_ host: NSView, scheme: ColorScheme) async throws -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.minX + 20, y: screen.minY + 20,
            width: 1160, height: 500), styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitForCondition { window.toolbar != nil }
        try await BoxWindowCaptureSupport.settle(window)
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 1160, height: 700))
        frame.size.height = min(frame.height, screen.height)
        frame.origin = NSPoint(x: screen.minX + 20, y: screen.maxY - frame.height)
        window.setFrame(frame, display: true)
        return window
    }

    private func capture(_ window: NSWindow, surface: String, scheme: ColorScheme) async throws {
        try await BoxWindowCaptureSupport.settle(window)
        let name = "\(surface)-\(scheme == .light ? "light" : "dark")"
        let labels = try recognize(window, name: name).map(\.text)
        let expected = SharedTimestamp.string(now.addingTimeInterval(-37500), now: now)
        XCTAssertTrue(labels.contains { $0.contains(expected) }, "\(name): \(labels)")
        let minutes = SharedTimestamp.string(now.addingTimeInterval(-1500), now: now)
        XCTAssertTrue(labels.contains { $0.contains(minutes) }, "\(name): \(labels)")
    }

    private func recognize(_ window: NSWindow, name: String) throws -> [(text: String, frame: CGRect)] {
        try BoxWindowCaptureSupport.capture(window, directory: directory, name: name)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        try VNImageRequestHandler(url: url).perform([request])
        return request.results?.compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        } ?? []
    }
}
