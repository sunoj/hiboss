// Renders selectable Markdown using native text, semantic fonts, and Dynamic Type.
// Exports MessageMarkdownView for iOS and macOS message details and transcripts.
// Dependencies: SwiftUI and the Foundation-backed MessageMarkdown block parser.

import SwiftUI

public struct MessageMarkdownView: View {
    private let blocks: [MessageMarkdownBlock]

    public init(_ source: String) { blocks = MessageMarkdown.blocks(source) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: MessageMarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph:
            inline(block.text)
        case .heading(let level):
            inline(block.text).font(level == 1 ? .title2.bold() : .headline)
                .accessibilityAddTraits(.isHeader)
        case .item(let marker):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: marker).accessibilityHidden(true)
                inline(block.text)
            }
        case .quote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(.secondary).frame(width: 3)
                inline(block.text).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        case .code:
            Text(verbatim: block.text).font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        case .copy(let label):
            CopyableTextBlock(label: label, text: block.text)
        }
    }

    private func inline(_ text: String) -> some View {
        Text(MessageMarkdown.inline(text)).fixedSize(horizontal: false, vertical: true)
    }
}
