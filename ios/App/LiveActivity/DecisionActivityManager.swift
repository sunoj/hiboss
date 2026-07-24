// Starts, refreshes, and ends decision Live Activities from the app.
// Exports: DecisionActivityManager.sync driven by the inbox's pending list.
// Dependencies: ActivityKit, HibossKit HistoryMessage, shared attributes.

import ActivityKit
import Foundation
import HibossKit
import os

private let laLog = Logger(subsystem: "ai.hiboss.ios", category: "LiveActivity")

@MainActor
enum DecisionActivityManager {
    /// Reconciles running Live Activities with the current pending decisions:
    /// ends stale ones and starts one for the most urgent unshown decision.
    static func sync(pending: [HistoryMessage], alertsEnabled: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            laLog.error("Live Activities disabled; skipping (\(pending.count) pending)")
            return
        }
        laLog.info("sync: \(pending.count) pending, \(Activity<DecisionActivityAttributes>.activities.count) running")
        let running = Activity<DecisionActivityAttributes>.activities
        let pendingIDs = alertsEnabled ? Set(pending.map(\.id.rawValue)) : []

        for activity in running where !pendingIDs.contains(activity.attributes.messageID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard alertsEnabled else { return }
        let shown = Set(running.map(\.attributes.messageID))
        guard let top = pending.first(where: { !shown.contains($0.id.rawValue) }) else { return }
        // Only surface blocking-style decisions (they carry options) in the Island.
        guard !top.options.isEmpty else { return }

        let state = DecisionActivityAttributes.ContentState(
            body: top.body, options: top.options, priority: top.priority,
            deadline: top.expirationDate, resolved: false, content: top.content
        )
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
}
