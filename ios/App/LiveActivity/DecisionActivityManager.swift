// Starts, refreshes, and ends decision Live Activities from the app.
// Exports: DecisionActivityManager.sync, end, rankedMessages and topMessage (shared top decision).
// Dependencies: ActivityKit, HibossKit HistoryMessage, shared attributes, LiveActivityTokenRegistrar.

import ActivityKit
import Foundation
import HibossKit
import os

private let laLog = Logger(subsystem: "ai.hiboss.app", category: "LiveActivity")

@MainActor
enum DecisionActivityManager {
    /// Candidates must come from the loaded required-input list, never bounded history.
    static func rankedMessages(from requiredInputs: [HistoryMessage], now: Date = .now) -> [HistoryMessage] {
        snapshot(requiredInputs, now: now).decisions.map(\.message)
    }

    /// HibossKit's shared top decision, text-reply asks included, as the Mac Island shows it.
    static func topMessage(from requiredInputs: [HistoryMessage], now: Date = .now) -> HistoryMessage? {
        snapshot(requiredInputs, now: now).topDecision()?.message
    }

    private static func snapshot(_ requiredInputs: [HistoryMessage], now: Date) -> TodaySnapshot {
        TodaySnapshot(history: [], requiredInputs: requiredInputs, health: .loading,
                      coverageComplete: false, now: now)
    }

    /// Keeps the most urgent Home decision on the Island and retires lower-ranked activities.
    /// An existing activity gets fresh timing and submission state without creating another.
    static func sync(pending: [HistoryMessage], alertsEnabled: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            laLog.error("Live Activities disabled; skipping (\(pending.count) pending)")
            return
        }
        laLog.info(
            "sync: \(pending.count) pending, \(Activity<DecisionActivityAttributes>.activities.count) running"
        )
        let running = Activity<DecisionActivityAttributes>.activities
        let top = alertsEnabled ? topMessage(from: pending) : nil

        for activity in running where activity.attributes.messageID != top?.id.rawValue {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard let top else { return }
        let registrar = LiveActivityTokenRegistrar.shared
        for activity in running where activity.attributes.messageID == top.id.rawValue {
            registrar.observe(activity)
        }

        let state = DecisionActivityAttributes.ContentState(
            body: top.body, options: top.options, priority: top.priority,
            deadline: top.expirationDate, content: top.content,
            submitting: DecisionReplyGate.shared.inFlight[top.id]
        )
        if await updateExisting(id: top.id.rawValue, state: state, deadline: top.expirationDate) { return }
        let attributes = DecisionActivityAttributes(
            messageID: top.id.rawValue, project: top.project ?? top.displayName,
            agentName: top.displayName, meta: top.metaLine
        )
        let content = ActivityContent(state: state, staleDate: top.expirationDate)
        do {
            let activity = try request(attributes, content: content, pushType: registrar.pushType)
            registrar.observe(activity)
            laLog.info("started Live Activity \(activity.id) for \(top.id.rawValue)")
        } catch {
            laLog.error("Activity.request failed: \(error.localizedDescription)")
        }
    }

    /// A token-push request the system refuses still gets a local-only activity.
    private static func request(
        _ attributes: DecisionActivityAttributes,
        content: ActivityContent<DecisionActivityAttributes.ContentState>, pushType: PushType?
    ) throws -> Activity<DecisionActivityAttributes> {
        if pushType != nil,
           let activity = try? Activity.request(attributes: attributes, content: content, pushType: pushType) {
            return activity
        }
        return try Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    /// Ends one ask's activity at once, e.g. when a resolution push says it closed elsewhere.
    nonisolated static func end(messageID: String) async {
        for activity in Activity<DecisionActivityAttributes>.activities
        where activity.attributes.messageID == messageID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    nonisolated static func updateExisting(
        id: String, state: DecisionActivityAttributes.ContentState, deadline: Date?
    ) async -> Bool {
        guard let activity = Activity<DecisionActivityAttributes>.activities.first(where: {
            $0.attributes.messageID == id
        }) else { return false }
        var next = state
        let previous = activity.content.state
        if next.submitting == previous.submitting {
            next.submissionProgressVisible = previous.submissionProgressVisible
            next.submissionIsSlow = previous.submissionIsSlow
            next.replyFailed = previous.replyFailed
        }
        await activity.update(ActivityContent(state: next, staleDate: deadline))
        return true
    }
}
