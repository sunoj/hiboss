// Measures option panel content while preserving the native notch geometry.
// Exports: OptionPanelLayout for controller sizing and rendering tests.
// Dependencies: AppKit text metrics and HibossKit option models.

import AppKit
import HibossKit

enum OptionPanelLayout {
    private static let contentHorizontalPadding: CGFloat = 36
    private static let optionTextChrome: CGFloat = 46
    private static let verticalChrome: CGFloat = 86
    private static let optionVerticalPadding: CGFloat = 18
    private static let optionSpacing: CGFloat = 7
    private static let minimumOptionHeight: CGFloat = 35
    private static let optionMediaHeight: CGFloat = 128
    private static let minimumBodyViewportHeight: CGFloat = 56
    /// Reply input row plus the stack spacing above it.
    private static let replyFieldHeight: CGFloat = 28
    /// SwiftUI controls consume slightly more height than AppKit text metrics report.
    private static let controlLayoutReserve: CGFloat = 24

    static func expandedHeight(
        for message: OptionMessage,
        width: CGFloat = AppConstants.Island.width
    ) -> CGFloat {
        let contentWidth = width - contentHorizontalPadding
        let bodyHeight = max(
            minimumBodyViewportHeight,
            textHeight(
                message.body,
                font: .systemFont(ofSize: 15, weight: .semibold),
                width: contentWidth
            )
        )
        let optionWidth = contentWidth - optionTextChrome
        let optionHeights = message.options.map { option in
            let mediaHeight = hasMedia(for: option, in: message) ? optionMediaHeight : 0
            return max(
                minimumOptionHeight,
                max(
                    mediaHeight,
                    textHeight(option, font: .systemFont(ofSize: 13, weight: .medium), width: optionWidth)
                )
                    + optionVerticalPadding
            )
        }
        let gaps = CGFloat(max(optionHeights.count - 1, 0)) * optionSpacing
        let optionsHeight: CGFloat
        if message.metadata?.optionMedia.isEmpty ?? true {
            let rows = stride(from: 0, to: message.options.count, by: 2).map { index in
                let options = message.options[index..<min(index + 2, message.options.count)]
                return max(24, options.map {
                    textHeight($0, font: .preferredFont(forTextStyle: .body), width: optionWidth / 2)
                }.max() ?? 0)
            }
            optionsHeight = rows.reduce(0, +) + CGFloat(max(0, rows.count - 1)) * 8
        } else {
            optionsHeight = optionHeights.reduce(0, +) + gaps
        }
        let supporting = supportingHeight(for: message, width: contentWidth)
        let chrome: CGFloat = verticalChrome + replyFieldHeight + controlLayoutReserve + 28
        return ceil(chrome + bodyHeight + optionsHeight + supporting)
    }

    private static func supportingHeight(for message: OptionMessage, width: CGFloat) -> CGFloat {
        var height: CGFloat = 0
        if let content = message.content, !content.isEmpty {
            height += textHeight(content, font: .preferredFont(forTextStyle: .body), width: width) + 8
        }
        if let option = message.defaultOption {
            let copy = DecisionDefaultLine.text(option: option, expiresAt: message.expirationDate, now: .now)
            height += textHeight(copy, font: .preferredFont(forTextStyle: .caption1), width: width) + 8
        }
        return height
    }

    private static func textHeight(_ text: String, font: NSFont, width: CGFloat) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(bounds.height)
    }

    private static func hasMedia(for option: String, in message: OptionMessage) -> Bool {
        let normalizedOption = option.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.metadata?.optionMedia.contains {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedOption
        } == true
    }
}

