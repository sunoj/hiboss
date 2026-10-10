// Renders option thumbnails beside native answer controls and opens full-size media.
// Exports: OptionMediaPicker for the island and standard option window.
// Dependencies: SwiftUI, HibossKit OptionMedia, and existing OptionButton.

import HibossKit
import SwiftUI

struct OptionMediaPicker: View {
    let options: [String]
    let media: [OptionMedia]
    let defaultOption: String?
    var allowsChoosing = true
    var isSubmitting = false
    let choose: (String) -> Void
    @State private var selectedMedia: OptionMedia?
    @State private var sendingOption: String?

    var body: some View {
        VStack(spacing: 7) {
            ForEach(options, id: \.self) { option in
                if let optionMedia = media(for: option) {
                    OptionMediaRow(
                        option: option,
                        media: optionMedia,
                        isDefault: option == defaultOption,
                        allowsChoosing: allowsChoosing && !isSubmitting && sendingOption == nil,
                        isSending: sendingOption == option,
                        choose: send,
                        openMedia: { selectedMedia = optionMedia }
                    )
                } else {
                    OptionButton(title: option, isDefault: option == defaultOption,
                                 isSending: sendingOption == option) {
                        send(option)
                    }
                    .disabled(!allowsChoosing || isSubmitting || sendingOption != nil)
                }
            }
        }
        .popover(item: $selectedMedia) { media in
            OptionMediaPopover(media: media)
        }
        .onChange(of: isSubmitting) { _, sending in
            if !sending { sendingOption = nil }
        }
    }

    private func send(_ option: String) {
        guard allowsChoosing, !isSubmitting, sendingOption == nil else { return }
        sendingOption = option
        choose(option)
    }

    private func media(for option: String) -> OptionMedia? {
        let normalizedOption = option.trimmingCharacters(in: .whitespacesAndNewlines)
        return media.first {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedOption
        }
    }
}

private struct OptionMediaRow: View {
    let option: String
    let media: OptionMedia
    let isDefault: Bool
    let allowsChoosing: Bool
    let isSending: Bool
    let choose: (String) -> Void
    let openMedia: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            OptionMediaPreview(media: media, openMedia: openMedia)
            OptionButton(title: option, isDefault: isDefault, isSending: isSending) {
                choose(option)
            }
            .disabled(!allowsChoosing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OptionMediaPreview: View {
    let media: OptionMedia
    let openMedia: () -> Void
    var showsCaption = true

    var body: some View {
        VStack(spacing: 4) {
            Button(action: openMedia) {
                OptionMediaImage(url: media.url, maxPixelSize: 264)
                .frame(width: 132, height: 96)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Open image for \(media.label)"))

            if showsCaption, let caption = media.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 132, alignment: .leading)
            }
        }
    }
}

struct OptionMediaPopover: View {
    let media: OptionMedia
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(media.label).font(.headline)
                Spacer()
                Button(L("Close"), systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly).keyboardShortcut(.cancelAction)
            }
            OptionMediaImage(url: media.url).onTapGesture { }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let caption = media.caption, !caption.isEmpty {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 720, height: 560)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onExitCommand { dismiss() }
    }
}
