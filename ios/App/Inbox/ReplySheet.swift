// Sheet for answering a decision with a listed option or a free-text reply.
// Exports: ReplySheet presented from a pending card's overflow action.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import HibossKit
import SwiftUI

struct ReplySheet: View {
    let message: HistoryMessage
    var onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message.displayName).hbLabel().foregroundStyle(Theme.ink3)
            Text(message.body)
                .font(.hbSmall)
                .foregroundStyle(Theme.ink2)
                .lineLimit(3)

            if !message.options.isEmpty {
                VStack(spacing: 8) {
                    ForEach(message.options, id: \.self) { option in
                        OptionButton(title: option, style: .secondary, alignment: .leading) {
                            onSend(option); dismiss()
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Type a reply…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.hbBody)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 42)
                    .background(Theme.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.line2, lineWidth: 1)
                    )
                OptionButton(title: "Send", style: .primary) {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSend(trimmed); dismiss()
                }
                .frame(width: 84)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
    }
}
