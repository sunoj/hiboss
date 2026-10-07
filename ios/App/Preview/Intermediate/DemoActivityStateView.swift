// Hosts the exact Live Activity reply-control component for simulator rendering evidence.
// Exports DemoActivityStateView, selected only by the demo activity flag.
// Dependencies: SwiftUI, DecisionActivityControls, Theme and synthetic activity content.

import SwiftUI

struct DemoActivityStateView: View {
    @State private var state = DecisionActivityAttributes.ContentState(
        body: "Run migration?", options: ["Approve", "Reject"], priority: "high",
        deadline: nil, content: nil, submitting: "Reject"
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live Activity").font(.hbH2).foregroundStyle(Theme.ink)
            DecisionActivityControls(messageID: "demo-activity", state: state,
                                     foreground: Theme.onAccent, primaryBackground: Theme.positive,
                                     secondaryBackground: Theme.ink)
        }.padding(16).background(Theme.paper)
            .task {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    state.submissionProgressVisible = true
                    try await Task.sleep(for: .milliseconds(7_700))
                    state.submissionIsSlow = true
                } catch { return }
            }
    }
}
