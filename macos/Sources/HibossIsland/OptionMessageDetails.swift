// Collapsible message details under the live question: a short preview that expands to Markdown.
// Exports: OptionMessageDetails and OptionDetailsPolicy (the pure length policy).
// Dependencies: SwiftUI and HibossKit's MessageMarkdown parser and view.

import HibossKit
import SwiftUI

/// Decides whether details need a toggle: more than `previewLineCount` visual lines in the
/// island's text column. Wide (CJK, kana, Hangul, fullwidth) characters take two units.
enum OptionDetailsPolicy {
    static let previewLineCount = 3
    static let unitsPerLine = 56

    static func isLong(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count <= previewLineCount else { return true }
        let visual = lines.reduce(0) { total, line in
            total + max(1, (widthUnits(line) + unitsPerLine - 1) / unitsPerLine)
        }
        return visual > previewLineCount
    }

    static func widthUnits(_ line: String) -> Int {
        line.unicodeScalars.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF,
             0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}

/// The asker's `--content`, collapsed to a short preview when it is long.
/// The expanded flag is owned by the caller so both `ViewThatFits` branches agree.
struct OptionMessageDetails: View {
    let text: String
    @Binding var isExpanded: Bool

    var body: some View {
        let isLong = OptionDetailsPolicy.isLong(text)
        VStack(alignment: .leading, spacing: 6) {
            details(showsAll: isExpanded || !isLong)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityIdentifier("island.details")
            if isLong { toggle }
        }
    }

    @ViewBuilder
    private func details(showsAll: Bool) -> some View {
        if showsAll {
            MessageMarkdownView(text, cards: false)
        } else {
            Text(MessageMarkdown.inline(text))
                .lineLimit(OptionDetailsPolicy.previewLineCount)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toggle: some View {
        Button { isExpanded.toggle() } label: {
            Label(isExpanded ? L("Collapse message") : L("Show full message"),
                systemImage: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("island.details.toggle")
        .accessibilityValue(isExpanded ? L("Expanded") : L("Collapsed"))
    }
}
