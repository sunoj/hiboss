// Exercises server list/stream coverage and all macOS decision surfaces through real stores.
// Exports: RequiredInputFlowTests and a controllable required-input service.
// Dependencies: XCTest, AppKit, HibossKit, RequiredInputStore, and OverviewStore.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class RequiredInputFlowTests: XCTestCase {
    func testThreeQueuedInputsRankAndAgreeAcrossTodayIslandBadgeAndSession() async throws {
        let required = fixtures()
        let api = ControlledRequiredInputs(messages: required)
        let inputs = RequiredInputStore()
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        inputs.connect(api)
        defer { inputs.disconnect() }
        try await waitForCondition { inputs.state.ready && inputs.state.loaded }

        _ = NSApplication.shared
        let suite = "RequiredInputFlowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.playsSound = false
        let controller = IslandPanelController(flow: flow, settings: settings, overview: overview)
        defer {
            controller.panel.close()
            controller.optionWindow.close()
        }
        try await waitForCondition { controller.panel.isVisible }
        let host = try XCTUnwrap(controller.panel.contentView as? BoxDropHostingView)
        XCTAssertTrue(host.rootView.overview === overview)
        let snapshot = overview.snapshot
        XCTAssertEqual(snapshot.today.decisions.map(\.id), ["auto", "blocked", "high"])
        XCTAssertEqual(snapshot.count(.needsYou), 3)
        XCTAssertEqual(snapshot.attention, snapshot.today.decisions)
        XCTAssertEqual(IslandAttention.presentation(snapshot: snapshot.today)?.message.id,
            snapshot.today.decisions.first?.id)
        XCTAssertEqual(snapshot.today.sessionDirectory.needsYou.count, 3)
        XCTAssertEqual(SessionContext(id: "blocked", snapshot: snapshot, inventory: []).decisions
            .map(\.id), ["blocked"])
        let button = NSButton()
        AppIdentity.configure(button, count: snapshot.today.decisions.count)
        XCTAssertEqual(button.title.trimmingCharacters(in: .whitespaces), "3")
    }

    func testHistoryAndLiveOnlyDecisionsNeverOpen() {
        let history = fixtures()
        let live = OptionMessage.fixture(id: "live-only", options: ["Ship"])
        let snapshot = OverviewSnapshot(history: history, live: live, now: .now)
        XCTAssertTrue(snapshot.today.decisions.isEmpty)
        XCTAssertTrue(snapshot.today.sessionDirectory.needsYou.isEmpty)
        XCTAssertEqual(snapshot.count(.needsYou), 0)
        XCTAssertNil(IslandAttention.presentation(snapshot: snapshot.today))
    }

    func testResolvedEventRemovesImmediatelyAndRefetchCannotReviveStaleDecision() async throws {
        let messages = fixtures()
        let api = ControlledRequiredInputs(messages: messages)
        let inputs = RequiredInputStore()
        let overview = OverviewStore()
        overview.bind(flow: OptionFlowStore(), inputs: inputs)
        inputs.connect(api)
        defer { inputs.disconnect() }
        try await waitForCondition { inputs.state.coverageComplete }
        await api.blockFetch()
        inputs.refresh()
        try await api.waitForFetch(count: 2)
        await api.resolve("auto")
        try await waitForCondition { !inputs.state.messages.contains { $0.id == "auto" } }
        XCTAssertEqual(overview.snapshot.today.decisions.map(\.id), ["blocked", "high"])
        try await api.waitForFetch(count: 3)
        await api.releaseFetches()
        try await waitForCondition { inputs.state.coverageComplete }
        XCTAssertEqual(overview.snapshot.today.decisions.map(\.id), ["blocked", "high"])
        XCTAssertEqual(IslandAttention.presentation(snapshot: overview.snapshot.today)?.message.id, "blocked")
    }

    func testReadyAndSuccessfulListLoadAreBothRequiredForCoverage() async throws {
        let api = ControlledRequiredInputs(messages: [], sendsReady: false)
        let inputs = RequiredInputStore()
        inputs.connect(api)
        defer { inputs.disconnect() }
        try await api.waitForStream()
        await api.blockFetch()
        await api.send(.message(fixtures()[0]))
        try await waitForCondition { inputs.state.messages.count == 1 }
        XCTAssertFalse(inputs.state.coverageComplete)
        await api.replace([])
        await api.send(.ready)
        try await waitForCondition { inputs.state.ready }
        XCTAssertFalse(inputs.state.coverageComplete)
        try await api.waitForFetch(count: 1)
        await api.releaseFetches()
        try await waitForCondition { inputs.state.coverageComplete }
        XCTAssertTrue(inputs.state.messages.isEmpty)
        await api.finish()
        try await waitForCondition { !inputs.state.ready }
        XCTAssertFalse(inputs.state.coverageComplete)
    }

    func testMessageAndRefetchReplaceTheListWithoutHistory() async throws {
        let api = ControlledRequiredInputs(messages: [])
        let inputs = RequiredInputStore()
        inputs.connect(api)
        defer { inputs.disconnect() }
        try await waitForCondition { inputs.state.coverageComplete }
        await api.send(.message(fixtures()[1]))
        try await waitForCondition { inputs.state.coverageComplete && inputs.state.messages.count == 1 }
        await api.replace([])
        inputs.refresh()
        try await waitForCondition { inputs.state.coverageComplete && inputs.state.messages.isEmpty }
    }

    func testFailedFetchCannotClaimCoverageAndRetryRecovers() async throws {
        let api = ControlledRequiredInputs(messages: [])
        await api.failFetch()
        let inputs = RequiredInputStore()
        inputs.connect(api)
        defer { inputs.disconnect() }
        try await waitForCondition { inputs.state.failed }
        XCTAssertFalse(inputs.state.coverageComplete)
        await api.replace(fixtures())
        inputs.refresh()
        try await waitForCondition { inputs.state.coverageComplete }
        XCTAssertEqual(inputs.state.messages.count, 3)
        inputs.disconnect()
        XCTAssertTrue(inputs.state.messages.isEmpty)
        XCTAssertFalse(inputs.state.coverageComplete)
    }

    func testFullHistoryPageDoesNotLimitRequiredInputCoverage() async throws {
        let inputs = RequiredInputStore()
        let api = ControlledRequiredInputs(messages: fixtures())
        let flow = OptionFlowStore()
        let overview = OverviewStore()
        overview.bind(flow: flow, inputs: inputs)
        let history = (0..<AppConstants.API.historyLimit).map {
            AttentionTestSupport.ask(id: MessageID(rawValue: "notice-\($0)"), options: [], now: .now)
        }
        flow.connect(api: ScriptedBossAPI(messages: [], history: history))
        inputs.connect(api)
        defer {
            inputs.disconnect()
            flow.disconnect()
        }
        try await waitForCondition { flow.historyState == .loaded && inputs.state.coverageComplete }
        XCTAssertTrue(overview.snapshot.today.coverageComplete)
        XCTAssertEqual(overview.snapshot.today.decisions.count, 3)
        overview.setQuestionnaireCoverage(false)
        XCTAssertFalse(overview.snapshot.today.coverageComplete)
        overview.setQuestionnaireCoverage(true)
        XCTAssertTrue(overview.snapshot.today.coverageComplete)
    }

    func testAccountChangeDiscardsOldListAndLateFetch() async throws {
        let old = ControlledRequiredInputs(messages: fixtures())
        await old.blockFetch()
        let inputs = RequiredInputStore()
        inputs.connect(old)
        try await old.waitForFetch(count: 1)
        let replacement = ControlledRequiredInputs(messages: [])
        inputs.connect(replacement)
        defer { inputs.disconnect() }
        try await waitForCondition { inputs.state.coverageComplete }
        await old.releaseFetches()
        XCTAssertTrue(inputs.state.messages.isEmpty)
        XCTAssertTrue(inputs.state.coverageComplete)
    }

    private func fixtures() -> [HistoryMessage] {
        let now = Date.now
        return [
            AttentionTestSupport.ask(id: "high", priority: "high", options: ["Review"], now: now),
            AttentionTestSupport.ask(id: "blocked", options: ["Approve"], sessionStatus: "waiting", now: now),
            AttentionTestSupport.ask(id: "auto", options: ["Ship", "Hold"], defaultOption: "Hold",
                expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(600)), now: now)
        ]
    }
}

actor ControlledRequiredInputs: RequiredInputServing {
    private var messages: [HistoryMessage]
    private let sendsReady: Bool
    private var continuation: AsyncThrowingStream<RequiredInputEvent, Error>.Continuation?
    private var waits: [(CheckedContinuation<[HistoryMessage], Error>, [HistoryMessage])] = []
    private var fetchCount = 0
    private var blocked = false
    private var failing = false

    init(messages: [HistoryMessage], sendsReady: Bool = true) {
        self.messages = messages
        self.sendsReady = sendsReady
    }

    func requiredInputStream() -> AsyncThrowingStream<RequiredInputEvent, Error> {
        AsyncThrowingStream {
            continuation = $0
            if sendsReady { $0.yield(.ready) }
        }
    }

    func fetchRequiredInputs() async throws -> [HistoryMessage] {
        fetchCount += 1
        if failing { throw TestError.rejected }
        if blocked {
            return try await withCheckedThrowingContinuation { waits.append(($0, messages)) }
        }
        return messages
    }

    func send(_ event: RequiredInputEvent) {
        if case let .message(message) = event {
            messages.removeAll { $0.id == message.id }
            messages.append(message)
        }
        continuation?.yield(event)
    }

    func resolve(_ id: MessageID) {
        messages.removeAll { $0.id == id }
        continuation?.yield(.resolved(id))
    }

    func replace(_ messages: [HistoryMessage]) {
        self.messages = messages
        failing = false
    }

    func blockFetch() { blocked = true }
    func failFetch() { failing = true }
    func finish() { continuation?.finish() }

    func waitForFetch(count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while fetchCount < count {
            guard ContinuousClock.now < deadline else { throw TestError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitForStream() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while continuation == nil {
            guard ContinuousClock.now < deadline else { throw TestError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func releaseFetches() {
        blocked = false
        let waits = waits
        self.waits = []
        for (wait, snapshot) in waits { wait.resume(returning: snapshot) }
    }
}
