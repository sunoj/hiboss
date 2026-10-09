// Exercises snapshot churn and authoritative resolution through the real panel controller.
// Exports: IslandPresentationRegressionTests for focus, animation, and resolved linger.
// Dependencies: XCTest, AppKit, required-input service, OptionFlowStore, and OverviewStore.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class IslandPresentationRegressionTests: XCTestCase {
    func testRepeatedSnapshotsWithSameLeadingDecisionNeverPresentOrActivateAgain() async throws {
        let question = AttentionTestSupport.ask(id: "question", options: ["Ship"], now: .now)
        let overview = OverviewStore()
        let settings = settings()
        settings.presentationMode = .window
        var activations = 0
        let geometry = IslandNotchFixtures.macBook14
        let controller = IslandPanelController(flow: OptionFlowStore(), settings: settings,
            overview: overview, screens: { [geometry] }, activate: { activations += 1 })
        defer {
            controller.panel.close()
            controller.optionWindow.close()
        }
        update(overview, question: question, tick: 0)
        XCTAssertEqual(activations, 1)
        for tick in 1...4 { update(overview, question: question, tick: tick) }
        XCTAssertEqual(activations, 1, "Health timestamps and history refreshes must not activate the app")
        settings.presentationMode = .island
        try await waitForCondition { controller.panel.alphaValue == 1 }
        let frame = controller.panel.frame
        controller.panel.alphaValue = 0.7
        for tick in 5...8 { update(overview, question: question, tick: tick) }
        XCTAssertEqual(controller.panel.frame, frame)
        XCTAssertEqual(controller.panel.alphaValue, 0.7, accuracy: 0.001,
            "Same-decision snapshots must not restart the collapsed/alpha-zero opening animation")
        let next = AttentionTestSupport.ask(id: "next", options: ["Hold"], now: .now)
        settings.presentationMode = .window
        XCTAssertEqual(activations, 2)
        update(overview, question: next, tick: 9)
        XCTAssertEqual(activations, 3, "A new leading decision still presents")
    }

    func testServerRemovalKeepsResolvedCardVisibleUntilFlowLingerEnds() async throws {
        let message = OptionMessage.fixture(id: "resolved", options: ["Ship", "Hold"])
        let question = TodayProjection.historyMessage(from: message)
        let api = ControlledRequiredInputs(messages: [question])
        let inputs = RequiredInputStore()
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        inputs.connect(api)
        try await waitForCondition { inputs.state.coverageComplete }
        let controller = IslandPanelController(flow: flow, settings: settings(), overview: overview,
            screens: { [IslandNotchFixtures.macBook14] })
        defer {
            inputs.disconnect()
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        flow.connect(api: ScriptedBossAPI(events: [.message(message),
            .resolved(OptionResolution(id: message.id, status: .replied, answer: "Ship", source: "Phone"))],
            eventInterval: .milliseconds(100)))
        try await waitForCondition {
            if case .resolved = flow.presentationState { return true }
            return false
        }
        await api.resolve(message.id)
        try await waitForCondition {
            inputs.state.coverageComplete && overview.snapshot.today.decisions.isEmpty
        }
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertEqual(IslandAttention.presentation(snapshot: overview.snapshot.today,
            active: flow.activeMessage, state: flow.presentationState)?.message.id, message.id)
        XCTAssertTrue(islandTestOverview(flow: flow).snapshot.today.decisions.isEmpty,
            "Rendering fixtures must remove a resolved decision just like the server")
        try await waitForCondition(timeout: .seconds(4)) { flow.activeMessage == nil }
        XCTAssertFalse(controller.panel.isVisible)
    }

    private func update(_ overview: OverviewStore, question: HistoryMessage, tick: Int) {
        let now = Date.now.addingTimeInterval(Double(tick))
        overview.update(history: [question], live: nil, now: now, health: .live(checkedAt: now),
            coverageComplete: true, requiredInputs: [question], requiredInputLoaded: true)
    }

    func testResolutionUpdatesInPlaceAndDifferentLeaderStillPresents() async throws {
        for mode in [OptionPresentationMode.window, .island] {
            try await assertResolutionUpdatesInPlace(mode: mode)
        }
    }

    private func assertResolutionUpdatesInPlace(mode: OptionPresentationMode) async throws {
        let message = OptionMessage.fixture(id: "resolved", options: ["Ship", "Hold"])
        let api = ControlledRequiredInputs(messages: [TodayProjection.historyMessage(from: message)])
        let inputs = RequiredInputStore()
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        inputs.connect(api)
        try await waitForCondition { inputs.state.coverageComplete }
        let settings = settings()
        settings.presentationMode = mode
        var activations = 0
        let controller = IslandPanelController(flow: flow, settings: settings, overview: overview,
            screens: { [IslandNotchFixtures.macBook14] }, activate: { activations += 1 })
        defer {
            inputs.disconnect()
            flow.disconnect()
            controller.panel.close()
            controller.optionWindow.close()
        }
        flow.connect(api: ScriptedBossAPI(events: [.message(message),
            .resolved(OptionResolution(id: message.id, status: .replied,
                answer: "Ship", source: "Phone"))],
            eventInterval: .milliseconds(500)))
        try await waitForCondition {
            flow.activeMessage != nil && (mode == .window || controller.panel.alphaValue == 1)
        }
        let frame = controller.panel.frame
        controller.panel.alphaValue = 0.7
        let initialActivations = activations
        try await waitForCondition {
            if case .resolved = flow.presentationState { return true }
            return false
        }
        await api.resolve(message.id)
        try await waitForCondition { inputs.state.messages.isEmpty }
        let presentation = IslandAttention.presentation(snapshot: overview.snapshot.today,
            active: flow.activeMessage, state: flow.presentationState)
        XCTAssertEqual(presentation?.message.id, message.id)
        XCTAssertNil(presentation?.item, "The resolved content replaces the open card")
        XCTAssertEqual(activations, initialActivations, "Resolution must not activate the app")
        XCTAssertEqual(controller.panel.frame, frame)
        XCTAssertEqual(controller.panel.alphaValue, 0.7, accuracy: 0.001,
            "Resolution must not replay the opening animation")
        flow.disconnect()
        await api.send(.message(AttentionTestSupport.ask(id: "next", options: ["Review"], now: .now)))
        try await waitForCondition { overview.snapshot.today.decisions.first?.id == "next" }
        if mode == .window { XCTAssertEqual(activations, initialActivations + 1) }
        else { try await waitForCondition { controller.panel.alphaValue == 1 } }
    }

    private func settings() -> AppSettings {
        _ = NSApplication.shared
        let suite = "IslandPresentationRegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.playsSound = false
        return settings
    }
}
