// Exercises answerability while the real required-input store refetches and reconnects.
// Exports: RequiredInputRefreshTests with suspended fetches and snapshot observations.
// Dependencies: XCTest, Combine, HibossKit, and ControlledRequiredInputs.

import Combine
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class RequiredInputRefreshTests: XCTestCase {
    func testErroredStreamExpiresAfterThirtySecondsAndManualRefreshRecovers() async throws {
        let (inputs, overview, api, question) = try await loadedStore()
        defer { inputs.disconnect() }
        await api.finish(failing: true)
        try await waitForCondition { !inputs.state.ready }
        let clock = ContinuousClock()
        let interruptedAt = clock.now
        assertOpen(question, in: overview)
        try await clock.sleep(for: .seconds(29))
        assertOpen(question, in: overview)
        try await waitForCondition(timeout: .seconds(3)) {
            overview.snapshot.answerability.state(for: question.id) == .checking
        }
        XCTAssertGreaterThanOrEqual(interruptedAt.duration(to: clock.now), .seconds(29))
        XCTAssertFalse(overview.snapshot.answerability.permitsReply(to: question))
        XCTAssertTrue(SessionContext(id: question.sessionId ?? "", snapshot: overview.snapshot,
            inventory: []).replyTargets.isEmpty)
        inputs.refresh()
        try await api.waitForFetch(count: 2)
        try await waitForCondition { inputs.state.loaded && !inputs.state.refreshing }
        XCTAssertFalse(inputs.state.ready)
        assertOpen(question, in: overview)
    }

    func testRefreshKeepsLoadedDecisionsAnswerableUntilReplacementArrives() async throws {
        let (inputs, overview, api, question) = try await loadedStore()
        defer { inputs.disconnect() }
        var states: [DecisionAnswerState] = []
        let observation = overview.$snapshot.sink { states.append($0.answerability.state(for: question.id)) }
        defer { observation.cancel() }
        await api.blockFetch()
        await api.replace([])
        inputs.refresh()
        try await api.waitForFetch(count: 2)
        XCTAssertTrue(inputs.state.loaded)
        XCTAssertTrue(inputs.state.refreshing)
        assertOpen(question, in: overview)
        XCTAssertEqual(states, [.open])
        await api.releaseFetches()
        try await waitForCondition { !inputs.state.refreshing && inputs.state.messages.isEmpty }
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .closed)
        XCTAssertFalse(states.contains(.checking))
    }

    func testResolutionClosesOnlyItsDecisionWhileRefetchIsSuspended() async throws {
        let (inputs, overview, api, question) = try await loadedStore()
        defer { inputs.disconnect() }
        let resolved = AttentionTestSupport.ask(id: "resolved", options: ["Hold"], now: .now)
        await api.send(.message(resolved))
        try await waitForCondition { inputs.state.messages.count == 2 }
        try await api.waitForFetch(count: 2)
        var states: [DecisionAnswerState] = []
        let observation = overview.$snapshot.sink { states.append($0.answerability.state(for: question.id)) }
        defer { observation.cancel() }
        await api.blockFetch()
        await api.resolve(resolved.id)
        try await api.waitForFetch(count: 3)
        XCTAssertTrue(inputs.state.refreshing)
        XCTAssertEqual(overview.snapshot.answerability.state(for: resolved.id), .closed)
        assertOpen(question, in: overview)
        await api.releaseFetches()
        try await waitForCondition { inputs.state.coverageComplete && !inputs.state.refreshing }
        XCTAssertFalse(states.contains(.checking))
        assertOpen(question, in: overview)
    }

    func testEOFAndFailedStreamReconnectKeepLoadedDecisionsAnswerable() async throws {
        for failing in [false, true] {
            let (inputs, overview, api, question) = try await loadedStore(
                reconnectDelay: .milliseconds(20), staleListDelay: .milliseconds(150))
            defer { inputs.disconnect() }
            var states: [DecisionAnswerState] = []
            let observation = overview.$snapshot.sink {
                states.append($0.answerability.state(for: question.id))
            }
            defer { observation.cancel() }
            await api.blockFetch()
            await api.finish(failing: failing)
            try await waitForCondition { !inputs.state.ready }
            assertOpen(question, in: overview)
            try await api.waitForStream(count: 2)
            try await api.waitForFetch(count: 2)
            XCTAssertTrue(inputs.state.refreshing)
            assertOpen(question, in: overview)
            try await Task.sleep(for: .milliseconds(200))
            assertOpen(question, in: overview)
            await api.releaseFetches()
            try await waitForCondition { inputs.state.coverageComplete && !inputs.state.refreshing }
            XCTAssertFalse(states.contains(.checking))
            assertOpen(question, in: overview)
        }
    }

    func testRetriesWithoutReadinessDoNotExtendTheStaleDeadline() async throws {
        let (inputs, overview, api, question) = try await loadedStore(
            reconnectDelay: .milliseconds(10), staleListDelay: .milliseconds(150))
        defer { inputs.disconnect() }
        await api.suppressReadiness()
        await api.finish(failing: true)
        try await api.waitForStream(count: 2)
        assertOpen(question, in: overview)
        try await Task.sleep(for: .milliseconds(90))
        await api.finish(failing: true)
        try await api.waitForStream(count: 3)
        try await waitForCondition(timeout: .milliseconds(100)) {
            overview.snapshot.answerability.state(for: question.id) == .checking
        }
        XCTAssertFalse(inputs.state.loaded)
        await api.send(.ready)
        try await waitForCondition { inputs.state.coverageComplete }
        assertOpen(question, in: overview)
    }

    func testOfflineRefetchRenewsGraceAndAccountSwitchCancelsItsDeadline() async throws {
        let (inputs, overview, api, question) = try await loadedStore(staleListDelay: .milliseconds(200))
        defer { inputs.disconnect() }
        await api.finish()
        try await waitForCondition { !inputs.state.ready }
        try await Task.sleep(for: .milliseconds(100))
        inputs.refresh()
        try await api.waitForFetch(count: 2)
        try await waitForCondition { !inputs.state.refreshing }
        try await Task.sleep(for: .milliseconds(130))
        assertOpen(question, in: overview)
        let replacement = ControlledRequiredInputs(messages: [question])
        inputs.connect(replacement)
        try await waitForCondition { inputs.state.coverageComplete }
        try await Task.sleep(for: .milliseconds(200))
        assertOpen(question, in: overview)
    }

    func testCoverageFailureChecksUntilSuccessfulRetryAndAccountSwitchChecksAgain() async throws {
        let (inputs, overview, api, question) = try await loadedStore()
        defer { inputs.disconnect() }
        await api.failFetch()
        inputs.refresh()
        try await waitForCondition { inputs.state.failed }
        XCTAssertTrue(inputs.state.loaded)
        XCTAssertFalse(inputs.state.refreshing)
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .checking)
        XCTAssertFalse(overview.snapshot.answerability.permitsReply(to: question))
        await api.replace([question])
        await api.blockFetch()
        inputs.refresh()
        try await api.waitForFetch(count: 3)
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .checking)
        await api.releaseFetches()
        try await waitForCondition { inputs.state.coverageComplete }
        assertOpen(question, in: overview)
        let replacement = ControlledRequiredInputs(messages: [])
        await replacement.blockFetch()
        inputs.connect(replacement)
        try await replacement.waitForFetch(count: 1)
        XCTAssertTrue(inputs.state.messages.isEmpty)
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .checking)
        await replacement.releaseFetches()
        try await waitForCondition { inputs.state.coverageComplete }
        XCTAssertEqual(overview.snapshot.answerability.state(for: question.id), .closed)
    }

    private func loadedStore(reconnectDelay: Duration = .seconds(60),
                             staleListDelay: Duration = .seconds(30)) async throws
        -> (RequiredInputStore, OverviewStore, ControlledRequiredInputs, HistoryMessage) {
        let question = AttentionTestSupport.ask(id: "open", options: ["Ship"], now: .now)
        let api = ControlledRequiredInputs(messages: [question])
        let inputs = RequiredInputStore(reconnectDelay: reconnectDelay, staleListDelay: staleListDelay)
        let overview = OverviewStore()
        overview.bind(flow: OptionFlowStore(), inputs: inputs)
        inputs.connect(api)
        try await waitForCondition { inputs.state.coverageComplete }
        return (inputs, overview, api, question)
    }

    private func assertOpen(_ question: HistoryMessage, in overview: OverviewStore,
                            file: StaticString = #filePath, line: UInt = #line) {
        let snapshot = overview.snapshot
        XCTAssertEqual(snapshot.answerability.state(for: question.id), .open, file: file, line: line)
        XCTAssertTrue(snapshot.answerability.permitsReply(to: question), file: file, line: line)
        XCTAssertEqual(snapshot.today.decisions.map(\.id), [question.id], file: file, line: line)
        XCTAssertEqual(SessionContext(id: question.sessionId ?? "", snapshot: snapshot, inventory: [])
            .replyTargets.map(\.id), [question.id], file: file, line: line)
        XCTAssertEqual(IslandAttention.presentation(snapshot: snapshot.today)?.message.id,
            question.id, file: file, line: line)
    }
}
