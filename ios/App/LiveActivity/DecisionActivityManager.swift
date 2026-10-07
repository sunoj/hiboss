// Starts, refreshes, and ends decision Live Activities from the app.
// Exports: DecisionActivityManager.sync and rankedMessages using Home's attention order.
// Dependencies: ActivityKit, HibossKit HistoryMessage, shared attributes.

import ActivityKit
import Foundation
import HibossKit
import os

private let laLog = Logger(subsystem: "ai.hiboss.app", category: "LiveActivity")

@MainActor
enum DecisionActivityManager {
    static func rankedMessages(from messages: [HistoryMessage], now: Date = .now) -> [HistoryMessage] {
        AttentionModel.items(from: messages, now: now)
            .filter { !$0.options.isEmpty }
            .map(\.message)
    }

    /// Keeps the most urgent Home decision on the Island and retires lower-ranked activities.
    /// An existing activity gets fresh timing and submission state without creating another.
    static func sync(pending: [HistoryMessage], alertsEnabled: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            laLog.error("Live Activities disabled; skipping (\(pending.count) pending)")
            return
        }
        laLog.info("sync: \(pending.count) pending, \(Activity<DecisionActivityAttributes>.activities.count) running")
        let running = Activity<DecisionActivityAttributes>.activities
        let ranked = rankedMessages(from: pending)
        let top = alertsEnabled ? ranked.first : nil

        for activity in running where activity.attributes.messageID != top?.id.rawValue {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard let top else { return }

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
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: top.expirationDate)
            )
            laLog.info("started Live Activity \(activity.id) for \(top.id.rawValue)")
        } catch {
            laLog.error("Activity.request failed: \(error.localizedDescription)")
        }
    }

    nonisolated static func updateExisting(
        id: String, state: DecisionActivityAttributes.ContentState, deadline: Date?
    ) async -> Bool {
        guard let activity = Activity<DecisionActivityAttributes>.activities.first(where: {
            $0.attributes.messageID == id
        }) else { return false }
        await activity.update(ActivityContent(state: state, staleDate: deadline))
        return true
    }
}
