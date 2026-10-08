// Adaptive image choices reusing the existing thumbnail and media popover.
// Exports: HistoryOptionGrid and exact selection presentation helpers.
// Dependencies: SwiftUI, HibossKit, OptionMediaPreview, and OptionMediaPopover.

import HibossKit
import SwiftUI

enum HistoryOptionSelection {
    static func matches(_ option: String, _ other: String?) -> Bool {
        guard let other else { return false }
        return option.trimmingCharacters(in: .whitespacesAndNewlines)
            == other.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSelected(_ option: String, outcome: ThreadOutcome) -> Bool {
        switch outcome {
        case let .chosen(chosen, _), let .autoSelected(chosen?): matches(option, chosen)
        default: false
        }
    }

    static func symbol(_ option: String, outcome: ThreadOutcome) -> String {
        guard isSelected(option, outcome: outcome) else { return "circle" }
        if case .autoSelected = outcome { return "clock.arrow.circlepath" }
        return "checkmark.circle.fill"
    }
}

struct HistoryOptionGrid: View {
    let options: [String]
    let media: [OptionMedia]
    let defaultOption: String?
    let outcome: ThreadOutcome
    let isSubmitting: Bool
    let sendingOption: String?
    let choose: (String) -> Void
    @State private var selectedMedia: OptionMedia?

    private var imageOptions: [String] { options.filter { mediaFor($0) != nil } }

    var body: some View {
        if !imageOptions.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .top)],
                alignment: .leading, spacing: 12) {
                ForEach(Array(imageOptions.enumerated()), id: \.offset) { _, option in
                    if let media = mediaFor(option) { tile(option, media: media) }
                }
            }
            .popover(item: $selectedMedia) { OptionMediaPopover(media: $0) }
        }
    }

    private func tile(_ option: String, media: OptionMedia) -> some View {
        let selected = HistoryOptionSelection.isSelected(option, outcome: outcome)
        return VStack(alignment: .leading, spacing: 6) {
            OptionMediaPreview(media: media, openMedia: { selectedMedia = media }, showsCaption: false)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: HistoryOptionSelection.symbol(option, outcome: outcome))
                            .foregroundStyle(Color.accentColor)
                            .background(Color(nsColor: .windowBackgroundColor), in: Circle()).padding(4)
                    }
                }
            Text(option).font(.body).fixedSize(horizontal: false, vertical: true)
            if let caption = media.caption, !caption.isEmpty {
                Text(caption).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if outcome == .open {
                Button { choose(option) } label: {
                    HStack {
                        Text(option).fixedSize(horizontal: false, vertical: true)
                        if HistoryOptionSelection.matches(option, defaultOption) {
                            Text(L("default")).foregroundStyle(.secondary)
                        }
                        if sendingOption == option { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(.bordered).disabled(isSubmitting)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if selected { Rectangle().strokeBorder(Color.accentColor, lineWidth: 1) }
        }
        .opacity(outcome == .open || selected ? 1 : 0.6)
    }

    private func mediaFor(_ option: String) -> OptionMedia? {
        media.first { HistoryOptionSelection.matches(option, $0.label) }
    }
}
