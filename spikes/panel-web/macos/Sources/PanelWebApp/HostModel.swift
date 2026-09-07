// Native owner of fixture selection, draft state, bridge timing, and intents.
// Exports: HostModel.
// Dependencies: SwiftUI, Foundation, BridgeTypes, and FixtureLoader.

import Foundation
import os
import SwiftUI

@MainActor
final class HostModel: ObservableObject {
    @Published var fixtureName = "metric-panel"
    @Published private(set) var contentHeight: Double = 240
    @Published private(set) var logLines: [String] = []
    var mountRevision = 0
    var sendMessage: ((HostMessage) -> Void)?
    private var draft: [String: JSONValue] = [:]
    private var mountStartedAt: UInt64?
    private var pendingApply: (sequence: Int, startedAt: UInt64)?
    private var applyDurationsMs: [Double] = []
    private let logger = Logger(subsystem: "ai.hiboss.panel-web-spike", category: "measurement")

    init() {
        if let configured = UserDefaults.standard.string(forKey: "HIBOSS_FIXTURE"), configured == "metric-panel" || configured == "rollout-decision" { fixtureName = configured }
    }

    func selectFixture(_ name: String) { fixtureName = name; mountRevision += 1 }

    func mount() {
        do {
            let fixture = try FixtureLoader().load(named: fixtureName)
            draft = fixture.initialState
            mountStartedAt = DispatchTime.now().uptimeNanoseconds
            sendMessage?(HostMessage(kind: .mount, panelId: "spike-panel", fixture: fixture.name, definition: fixture.definition, state: fixture.initialState, sequence: nil, status: nil, appearance: "system"))
        } catch { append("mount failed: \(error)") }
    }

    func requestStatus(_ status: String) { sendMessage?(HostMessage(kind: .requestStatus, panelId: "spike-panel", fixture: nil, definition: nil, state: nil, sequence: nil, status: status, appearance: nil)) }

    func runApplyProbe() {
        guard pendingApply == nil else { return }
        applyDurationsMs.removeAll(keepingCapacity: true)
        sendNextApply(sequence: 1)
    }

    func handle(_ message: ViewMessage) {
        guard message.panelId == "spike-panel" else { return }
        switch message.kind {
        case .draftChanged: saveDraft(message.changes ?? [])
        case .actionRequested: append("action intent: \(message.action ?? "unknown") (not submitted)")
        case .contentSizeChanged: handleSize(message)
        case .renderFailed: append("renderer failure: \(message.classification ?? "unknown")")
        }
    }

    private func saveDraft(_ changes: [DraftChange]) {
        for change in changes where change.path == "/form/strategy" || change.path == "/form/trafficPercent" { draft[change.path] = change.value }
    }

    private func handleSize(_ message: ViewMessage) {
        if let height = message.contentHeight { contentHeight = height }
        if let start = mountStartedAt { append(String(format: "cold mount %.2f ms (contentSizeChanged after layout)", elapsedMs(since: start))); mountStartedAt = nil }
        guard let pending = pendingApply, message.observedSequence == pending.sequence else { return }
        applyDurationsMs.append(elapsedMs(since: pending.startedAt))
        pendingApply = nil
        if pending.sequence < 200 { sendNextApply(sequence: pending.sequence + 1) } else { append(percentiles()) }
    }

    private func sendNextApply(sequence: Int) {
        pendingApply = (sequence, DispatchTime.now().uptimeNanoseconds)
        let task: JSONValue = .object(["completed": .number(Double(sequence)), "label": .string("Probe")])
        sendMessage?(HostMessage(kind: .applyTaskState, panelId: "spike-panel", fixture: nil, definition: nil, state: ["task": task], sequence: sequence, status: nil, appearance: nil))
    }

    private func elapsedMs(since start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }

    private func percentiles() -> String {
        let sorted = applyDurationsMs.sorted()
        guard sorted.count == 200 else { return "apply probe incomplete: \(sorted.count)/200" }
        let p50 = sorted[99]; let p95 = sorted[189]
        return String(format: "apply latency n=200 p50 %.2f ms p95 %.2f ms", p50, p95)
    }

    private func append(_ line: String) { logLines = Array((logLines + [line]).suffix(6)); logger.info("\(line, privacy: .public)") }
}
