// Native choice buttons for a pending decision, shared by the Home card and message detail.
// Exports: DecisionOptions. Two options sit side by side at one shared row height; three or
// more stack vertically.
// Dependencies: SwiftUI, DecisionTiming (which option is the live timeout default).

import SwiftUI

struct DecisionOptions: View {
    let options: [String]
    let timing: DecisionTiming
    var submitting: String?
    let onChoose: (String) -> Void

    var body: some View {
        if options.count == 2 {
            // The row takes its tallest label's height and both buttons fill it, so a label that
            // wraps at large text never leaves its neighbour shorter.
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { button($0, alignment: .center) }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { button($0, alignment: .leading) }
            }
        }
    }

    @ViewBuilder
    private func button(_ option: String, alignment: Alignment) -> some View {
        let isDefault = timing.isAutoDefault(option)
        let control = Button { onChoose(option) } label: { label(option, alignment: alignment) }
            .frame(maxWidth: .infinity)
            .accessibilityValue(isDefault ? Text("Default") : Text(verbatim: ""))
        .accessibilityHint(isDefault ? Text("Selected automatically when time runs out") : Text(verbatim: ""))
        Group {
            if isDefault {
                control.prominentAction()
            } else {
                control.buttonStyle(.bordered)
            }
        }
        .disabled(submitting != nil)
    }

    private func label(_ option: String, alignment: Alignment) -> some View {
        HStack(spacing: 8) {
            // Agent-authored text: shown verbatim, never looked up in the catalog.
            Text(verbatim: option)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: alignment)
            if submitting == option.trimmingCharacters(in: .whitespacesAndNewlines) {
                DelayedProgressView(tint: timing.isAutoDefault(option) ? Theme.onAccent : Theme.ink)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .frame(maxHeight: alignment == .center ? .infinity : nil)
    }
}
