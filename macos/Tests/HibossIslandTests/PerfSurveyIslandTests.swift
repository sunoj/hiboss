// Opt-in controller-backed Island survey, skipped in normal tiers to protect the desktop.
// Exports: PerfSurveyIslandTests; HIBOSS_PERF_SURVEY is set only by perf-survey.sh.
// Dependencies: production controllers and reply bindings, loopback snapshot image fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class PerfSurveyIslandTests: XCTestCase {
    func testIslandModes() async throws {
        try PerfSurveyMetrics.enabled()
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        for name in ["collapsed", "short", "long", "images", "option window"] {
            guard PerfSurveyMetrics.accepts("Island " + name) else { continue }
            try await measure(name, baseURL: server.baseURL)
        }
    }

    private func measure(_ name: String, baseURL: String) async throws {
        _ = NSApplication.shared
        let settings = PerfSurveyFixtures.settings()
        if name == "option window" { settings.presentationMode = .window }
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let overview = islandTestOverview(flow: flow)
        let screen = try XCTUnwrap(NSScreen.main)
        let pointer = NSPoint(x: screen.frame.midX, y: screen.frame.maxY - 1)
        let controller = IslandPanelController(flow: flow, settings: settings, overview: overview,
            pointerLocation: { pointer })
        defer {
            flow.disconnect()
            PerfSurveyFixtures.close(controller.panel)
            PerfSurveyFixtures.close(controller.optionWindow)
        }
        let message = question(name, baseURL: baseURL)
        if name != "collapsed" {
            flow.connect(api: ScriptedBossAPI(messages: [message]))
            try await waitForCondition { flow.activeMessage?.id == message.id }
            try await waitForCondition {
                (name == "option window" ? controller.optionWindow : controller.panel).isVisible
            }
        } else {
            controller.dropReveal?.refreshPointer()
            try await waitForCondition { controller.panel.isVisible }
        }
        let window = name == "option window" ? controller.optionWindow : controller.panel
        var revision = 0
        try await PerfSurveyMetrics.measure("Island " + name,
            size: name == "collapsed" ? "0 questions" : "1 question / \(message.options.count) options",
            window: window, update: {
                if name == "collapsed" {
                    overview.update(history: [], live: nil, health: .live(checkedAt: .now))
                } else {
                    revision += 1
                    let binding = Binding(get: { controller.reply.drafts[message.id] ?? "" },
                        set: { controller.reply.drafts[message.id] = $0 })
                    binding.wrappedValue = "Run focused validation \(revision)."
                }
            }, interact: {
                settings.presentationMode = name == "option window" ? .island : .window
            })
    }

    private func question(_ name: String, baseURL: String) -> OptionMessage {
        let options = name == "long" ? (0..<12).map { "Review alternative \($0) with validation" }
            : ["Ship", "Hold"]
        let media = name == "images" ? options.map {
            OptionMedia(label: $0, url: baseURL + "/ship.png", caption: "Navigation preview")
        } : []
        return OptionMessage(id: "survey-question", body: name == "long"
            ? String(repeating: "Review the migration and verified rollback plan. ", count: 15)
            : "Which validation should run next?",
            metadata: MessageMetadata(options: options, optionMedia: media, defaultOption: options.last),
            expiresAt: AttentionTestSupport.iso(.now.addingTimeInterval(3600)))
    }
}
