// The focus card's message details: three lines, then the full Markdown on request.
// Exports: FocusMessagePreview.
// Dependencies: SwiftUI, MediaMarkdownView, Theme.

import SwiftUI

struct FocusMessagePreview: View {
    let content: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            if expanded {
                MediaMarkdownView(content).font(.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(preview).font(.subheadline).foregroundStyle(Theme.ink2).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if expanded || isLong {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Label(expanded ? LocalizedStringKey("Show less") : LocalizedStringKey("Show full message"),
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: ControlMetric.minTap, alignment: .leading)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.link)
                .accessibilityIdentifier("today-focus-details")
            }
        }
    }

    /// Inline Markdown only, so the clamped lines read as prose rather than markup.
    private var preview: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: content, options: options)) ?? AttributedString(content)
    }

    /// A rough fit test: more than three short lines, or any block Markdown, has more to show.
    private var isLong: Bool {
        content.count > 160 || content.split(separator: "\n").count > 3
            || content.contains("![") || content.contains("```")
    }
}
