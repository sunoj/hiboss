// Native reply controls shared by Live Activities and the simulator evidence fixture.
// Exports DecisionActivityControls; pending replies keep their mutually exclusive choices locked.
// Dependencies: SwiftUI, WidgetKit, RespondDecisionIntent and DecisionSubmissionNotice.

import SwiftUI
import WidgetKit

struct DecisionActivityControls: View {
    let messageID: String
    let state: DecisionActivityAttributes.ContentState
    let foreground: Color
    let primaryBackground: Color
    let secondaryBackground: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                ForEach(Array(state.options.prefix(2).enumerated()), id: \.offset) { index, option in
                    Button(intent: RespondDecisionIntent(messageID: messageID, choice: option)) {
                        HStack {
                            Text(verbatim: option)
                            if state.submissionProgressVisible == true,
                               state.submitting == option.trimmingCharacters(in: .whitespacesAndNewlines) {
                                ProgressView().tint(foreground).accessibilityLabel("Sending reply…")
                            }
                        }
                        .font(.callout.weight(.semibold)).foregroundStyle(foreground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(index == 0 ? primaryBackground : secondaryBackground,
                                    in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }.disabled(state.submitting != nil || state.completion != nil)
            DecisionSubmissionNotice(state: state)
        }
    }
}
