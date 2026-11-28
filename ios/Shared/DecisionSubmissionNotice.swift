// Readable slow-send and failure feedback shared by Live Activities and demo rendering.
// Exports DecisionSubmissionNotice; opening the app never resubmits the reply.
// Dependencies: SwiftUI and DecisionActivityAttributes content state.

import SwiftUI

let decisionActivityAppURL = URL(string: "hiboss://open")!

struct DecisionSubmissionNotice: View {
    let state: DecisionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.submissionIsSlow == true || state.replyFailed == true {
                if state.replyFailed == true { Text("Not sent").fontWeight(.semibold) }
                else { Text("Your reply is still sending.") }
                Link("Open HiBoss to check the connection", destination: decisionActivityAppURL)
                    .frame(minHeight: 28)
            }
        }.font(.footnote).fixedSize(horizontal: false, vertical: true)
    }
}
