// Readable slow-send and failure feedback shared by Live Activities and demo rendering.
// Exports DecisionSubmissionNotice; opening the app never resubmits the reply.
// Dependencies: SwiftUI and DecisionActivityAttributes content state.

import SwiftUI

struct DecisionSubmissionNotice: View {
    let state: DecisionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.submissionIsSlow == true || state.replyFailed == true {
                if state.replyFailed == true { Text("The reply couldn't be sent.") }
                else { Text("Your reply is still sending.") }
                if let destination = URL(string: "hiboss://") {
                    Link("Open HiBoss to check the connection", destination: destination)
                        .frame(minHeight: 44)
                }
            }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
