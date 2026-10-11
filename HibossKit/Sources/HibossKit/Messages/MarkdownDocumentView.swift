// Renders Markdown documents with selectable native text and horizontally scrollable tables.
// Exports: MarkdownDocumentView; wide tables do not widen the reading window.
// Dependencies: SwiftUI Grid, HibossKit MessageMarkdownView, and MarkdownDocumentSections.

import SwiftUI

public struct MarkdownDocumentView: View {
    private let source: String

    public init(source: String) { self.source = source }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(MarkdownDocumentSections.parse(source).enumerated()), id: \.offset) { _, section in
                switch section {
                case .text(let text):
                    MessageMarkdownView(text)
                case .table(let table):
                    tableView(table)
                }
            }
        }
        .font(.body)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableView(_ table: MarkdownDocumentTable) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 10) {
                row(table.header, table: table, isHeader: true)
                Divider().gridCellColumns(table.header.count)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                    row(cells, table: table, isHeader: false)
                }
            }.padding(12)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("message.attachment.markdown.table")
    }

    private func row(_ cells: [String], table: MarkdownDocumentTable, isHeader: Bool) -> some View {
        GridRow {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(MessageMarkdown.inline(cell))
                    .fontWeight(isHeader ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 90, maxWidth: 280, alignment: alignment(table.alignments[index]))
                    .gridColumnAlignment(horizontalAlignment(table.alignments[index]))
            }
        }
    }

    private func alignment(_ value: MarkdownDocumentTable.Alignment) -> Alignment {
        switch value { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }

    private func horizontalAlignment(_ value: MarkdownDocumentTable.Alignment) -> HorizontalAlignment {
        switch value { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
}
