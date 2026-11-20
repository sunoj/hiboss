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
        let described = !(item.message.metadata?.optionDescriptions.isEmpty ?? true)
        let layout = described
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(DecisionChoiceLayout())
        layout {
            ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                let description = item.message.metadata?.optionDescription(for: option)
                VStack(alignment: .leading, spacing: 8) {
                    if let media = media(for: option) {
                        OptionMediaPreview(media: media, openMedia: { selectedMedia = media })
                    }
                    choice(option, description: description, described: described,
                        primary: index == 0)
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

    /// The first option is the Ink primary. A system prominent button on this OS
    /// draws the same unfilled bezel as a bordered one, so the fill stays here.
    @ViewBuilder
    private func choice(_ option: String, description: String?, described: Bool, primary: Bool) -> some View {
        Button { send(option) } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: option)
                    OptionDescriptionText(text: description)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                if described { Spacer(minLength: 0) }
                if sendingOption == option {
                    ProgressView().controlSize(.small)
                    Text(L("Sending…")).font(.caption)
                }
            }
        }
        .buttonStyle(DecisionChoiceStyle(isPrimary: primary, described: described))
        .disabled(isSubmitting || sendingOption != nil)
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

/// Ink capsule for a one-line choice. A described choice uses a continuous
/// rectangle so two lines do not become a tall pill.
private struct DecisionChoiceStyle: ButtonStyle {
    let isPrimary: Bool
    var described = false

    func makeBody(configuration: Configuration) -> some View {
        if described {
            label(configuration, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            label(configuration, in: Capsule())
        }
    }

    private func label<S: InsettableShape>(_ configuration: Configuration, in shape: S) -> some View {
        configuration.label
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(isPrimary ? TodayStyle.ground : Color.primary)
            .background(isPrimary ? TodayStyle.ink : Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay { shape.strokeBorder(isPrimary ? Color.clear : Color(nsColor: .separatorColor), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(shape)
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
