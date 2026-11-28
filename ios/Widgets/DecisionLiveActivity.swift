// Live Activity for a pending decision: lock-screen card + Dynamic Island.
// Exports: DecisionLiveActivity widget configuration.
// Dependencies: ActivityKit, WidgetKit, SwiftUI, shared attributes + intent.

import ActivityKit
import SwiftUI
import WidgetKit

struct DecisionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DecisionActivityAttributes.self) { context in
            DecisionActivityCard(attributes: context.attributes, state: context.state)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let tint = DecisionActivityPriority.color(state.priority)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    DecisionActivityCard(attributes: context.attributes, state: state)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                HiBossBrandIcon(size: 18)
            } compactTrailing: {
                DecisionActivityCompactStatus(state: state)
            } minimal: {
                DecisionActivityMinimalStatus(state: state)
            }
            .keylineTint(tint)
        }
    }
}
