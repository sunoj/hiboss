// Shared decision choices for Today and the inspector, wrapping at the available width.
// Exports: DecisionChoices; the first native Button uses Ink, the others a border.
// Dependencies: SwiftUI Layout, HibossKit, TodayStyle, and existing media previews.

import HibossKit
import SwiftUI

struct DecisionChoices: View {
    @Environment(\.isEnabled) private var isEnabled
    let item: AttentionItem
    var isSubmitting = false
    let onChoose: (String) -> Void
    @State private var selectedMedia: OptionMedia?
    @State private var sendingOption: String?

    var body: some View {
        DecisionChoiceLayout {
            ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                VStack(alignment: .leading, spacing: 8) {
                    if let media = media(for: option) {
                        OptionMediaPreview(media: media, openMedia: { selectedMedia = media })
                    }
                    Button { send(option) } label: {
                        HStack(spacing: 6) {
                            Text(option)
                            if sendingOption == option {
                                ProgressView().controlSize(.small)
                                Text(L("Sending…")).font(.caption)
                            }
                        }
                    }
                    .buttonStyle(DecisionChoiceStyle(isPrimary: index == 0))
                    .disabled(isSubmitting || sendingOption != nil)
                }
            }
        }
        .popover(item: $selectedMedia) { media in OptionMediaPopover(media: media) }
        .onChange(of: isSubmitting) { _, sending in
            if !sending { sendingOption = nil }
        }
        .onChange(of: isEnabled) { _, enabled in
            if enabled && !isSubmitting { sendingOption = nil }
        }
    }

    private func send(_ option: String) {
        guard !isSubmitting, sendingOption == nil else { return }
        sendingOption = option
        onChoose(option)
    }

    private func media(for option: String) -> OptionMedia? {
        item.message.metadata?.optionMedia.first {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines)
                == option.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private struct DecisionChoiceStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isPrimary ? TodayStyle.ground : Color.primary)
            .background(isPrimary ? TodayStyle.ink : TodayStyle.surface,
                in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isPrimary ? Color.clear : TodayStyle.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct DecisionChoiceLayout: Layout {
    private let spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrangement(subviews, width: bounds.width).frames
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(_ subviews: Subviews, width: CGFloat?) -> (size: CGSize, frames: [CGRect]) {
        let available = max(0, width ?? .greatestFiniteMagnitude)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(ideal.width, available), height: nil))
            if x > 0, x + size.width > available {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            usedWidth = max(usedWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), frames)
    }
}
