// Realistic bounded and scale fixtures for the opt-in macOS CPU survey.
// Exports: PerfSurveyFixtures; reuses snapshot message, session, Box and Progress fixtures.
// Dependencies: AppKit, SwiftUI, HibossKit and the existing snapshot fixture support.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
enum PerfSurveyFixtures {
    static func history(count: Int, sessions: Int, baseURL: String) -> [HistoryMessage] {
        let seed = PhaseBSnapshotFixtures.history(baseURL: baseURL) + SessionThreadFixtures.history()
        return (0..<count).map { index in
            let source = seed[index % seed.count]
            let session = index % sessions == 0 ? "hiboss" : "session-\(index % sessions)"
            return HistoryMessage(id: MessageID(rawValue: "message-\(index)"), body: source.body,
                agentName: source.agentName, direction: "agent_to_boss",
                status: index % 10 < 2 ? "delivered" : "replied", priority: source.priority,
                metadata: index % 10 < 2 ? source.metadata : nil,
                expiresAt: source.expiresAt,
                createdAt: AttentionTestSupport.iso(.now.addingTimeInterval(-Double(index * 5))),
                sessionId: session, sessionLabel: session, sessionBranch: "main",
                sessionStatus: index % 2 == 0 ? "waiting" : "working")
        }
    }

    static func inventory(count: Int) -> [ProjectSession] {
        (0..<count).map { index in
            ProjectSession(id: index == 0 ? "hiboss" : "session-\(index)", projectId: "project-\(index)",
                projectSlug: "Project \(index)", branch: "main", host: "Mac", agentName: "Build Agent",
                status: index % 2 == 0 ? "waiting" : "working",
                lastSeenAt: AttentionTestSupport.iso(.now.addingTimeInterval(-9)))
        }
    }

    static func window<V: View>(_ view: V, settings: Bool = false) throws -> NSWindow {
        _ = NSApplication.shared
        let size = settings ? NSSize(width: 900, height: 680) : NSSize(width: 1320, height: 820)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        let screen = try XCTUnwrap(NSScreen.main)
        let bounds = screen.visibleFrame
        let rect = NSRect(x: bounds.minX, y: bounds.minY + 20,
            width: min(size.width, bounds.width), height: min(size.height, bounds.height - 60))
        let window = NSWindow(contentRect: rect, styleMask: [.titled, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    static func settings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "PerfSurveyFixtures")!
        defaults.removePersistentDomain(forName: "PerfSurveyFixtures")
        let settings = AppSettings(defaults: defaults)
        settings.playsSound = false
        return settings
    }

    static func close(_ window: NSWindow) {
        window.contentView = nil
        window.close()
    }

    static func panels() async throws -> PanelsModel {
        let model = PanelsModel(api: try StubPanelsService(populated: true), demoMode: false, autoload: false)
        await model.load()
        return model
    }
}
