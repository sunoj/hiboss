// Selectable inline message text with explicit expand/collapse controls.
// Exports: HistoryMessageBody; searches reveal the full matching message.
// Dependencies: SwiftUI and HistoryReadingContent.

import SwiftUI

struct HistoryMessageBody: View {
    let content: HistoryReadingContent
    let isSearching: Bool
    @Binding var isExpanded: Bool
    let onCollapse: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { isExpanded || isSearching || !content.isLong }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(expanded ? content.fullText : content.preview)
                .font(.body).foregroundStyle(.primary).lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if content.isLong && !isSearching {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        isExpanded.toggle()
                    }
                    if !isExpanded { onCollapse() }
                } label: {
                    Label(expanded ? L("Collapse message") : L("Show full message"),
                        systemImage: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("history.expand")
                .accessibilityValue(expanded ? L("Expanded") : L("Collapsed"))
            }
        }
    }
}
