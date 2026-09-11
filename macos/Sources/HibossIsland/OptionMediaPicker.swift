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
    let choose: (String) -> Void
    @State private var selectedMedia: OptionMedia?

    var body: some View {
        VStack(spacing: 7) {
            ForEach(options, id: \.self) { option in
                if let optionMedia = media(for: option) {
                    OptionMediaRow(
                        option: option,
                        media: optionMedia,
                        isDefault: option == defaultOption,
                        allowsChoosing: allowsChoosing,
                        choose: choose,
                        openMedia: { selectedMedia = optionMedia }
                    )
                } else {
                    OptionButton(title: option, isDefault: option == defaultOption) {
                        choose(option)
                    }
                    .disabled(!allowsChoosing)
                }
            }
        }
        .popover(item: $selectedMedia) { media in
            OptionMediaPopover(media: media)
        }
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
    let choose: (String) -> Void
    let openMedia: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            OptionMediaPreview(media: media, openMedia: openMedia)
            OptionButton(title: option, isDefault: isDefault) {
                choose(option)
            }
            .disabled(!allowsChoosing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OptionMediaPreview: View {
    let media: OptionMedia
    let openMedia: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: openMedia) {
                AsyncImage(url: URL(string: media.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 96)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Open image for \(media.label)"))

            if let caption = media.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 132, alignment: .leading)
            }
        }
    }
}

private struct OptionMediaPopover: View {
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
            AsyncImage(url: URL(string: media.url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().onTapGesture { }
                case .failure:
                    ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
                case .empty:
                    ProgressView()
                @unknown default:
                    ContentUnavailableView("Image unavailable", systemImage: "photo")
                }
            }
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
