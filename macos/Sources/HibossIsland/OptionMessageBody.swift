// Renders the live question at natural height and scrolls only when its viewport is capped.
// Exports: OptionMessageBody, with a one-line viewport floor and natural height preference.
// Dependencies: SwiftUI, OptionMessageDetails, and MessageAttachmentView.

import SwiftUI
import HibossKit

/// Renders a complete short question directly and adds scrolling only when the
/// available panel height cannot contain the question.
struct OptionMessageBody: View {
    static let minimumHeight: CGFloat = 20

    let text: String
    var details: String? = nil
    let attachment: MessageAttachment?
    /// Owned here, outside `ViewThatFits`, so both branches render the same state.
    @State private var detailsExpanded = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical, showsIndicators: true) { content }
        }
        .frame(minHeight: Self.minimumHeight, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("island.question")
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: QuestionTextBounds.self,
                        value: geometry.frame(in: .named("island.content")))
                })
                .frame(maxWidth: .infinity, alignment: .leading)
            if let details {
                OptionMessageDetails(text: details, isExpanded: $detailsExpanded)
            }
            if let attachment {
                MessageAttachmentView(attachment: attachment)
            }
        }
        .padding(.trailing, 8)
        .reportNaturalHeight(.question)
    }
}
