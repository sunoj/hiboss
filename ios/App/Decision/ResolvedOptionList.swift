// Every option of a decision that is no longer open, read-only, with the recorded answer marked.
// Exports: ResolvedOptionList, shared by the message detail and the session transcript.
// Dependencies: SwiftUI, HibossKit metadata and DecisionSettlement.

import HibossKit
import SwiftUI

struct ResolvedOptionList: View {
    let options: [String]
    var metadata: MessageMetadata? = nil
    let settlement: DecisionSettlement?
    /// Adds the recorded answer as a "Custom reply" row when it matches no option.
    var showsCustomAnswer = false

    /// Options without a media tile; OptionMediaComparison already shows and marks those.
    static func textOptions(_ options: [String], metadata: MessageMetadata?) -> [String] {
        let media = (metadata?.optionMedia ?? []).map { trimmed($0.label) }
        return options.filter { !media.contains(trimmed($0)) }
    }

    private var answer: String? {
        guard let value = settlement.map({ Self.trimmed($0.answer) }), !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        if !options.isEmpty || (showsCustomAnswer && answer != nil) {
            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(options, id: \.self) { option in
                    row(option, chosen: Self.trimmed(option) == answer)
                }
                if showsCustomAnswer, let answer, !options.contains(where: { Self.trimmed($0) == answer }) {
                    row(answer, chosen: true, custom: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("resolved-options")
        }
    }

    private func row(_ text: String, chosen: Bool, custom: Bool = false) -> some View {
        let automatic = chosen && settlement?.isAutoDefault == true
        return HStack(spacing: Space.s) {
            Image(systemName: chosen ? (settlement?.symbol ?? "checkmark.circle.fill") : "circle")
                .foregroundStyle(chosen ? Theme.accent : Theme.ink2)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: text).foregroundStyle(chosen ? Theme.ink : Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                OptionDescriptionText(text: metadata?.optionDescription(for: text))
                if custom { Text("Custom reply").font(.caption2).foregroundStyle(Theme.ink2) }
            }
            Spacer()
            if chosen {
                (automatic ? Text("Auto-selected") : Text("Selected")).font(.caption).foregroundStyle(
                    Theme.ink2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
