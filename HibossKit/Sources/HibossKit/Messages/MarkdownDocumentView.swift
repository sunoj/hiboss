// Renders Markdown documents with selectable native text and horizontally scrollable tables.
// Exports: MarkdownDocumentView; wide tables do not widen the reading window.
// Dependencies: SwiftUI Layout, HibossKit MessageMarkdownView, and MarkdownDocumentSections.

import SwiftUI

public struct MarkdownDocumentView: View {
    private let source: String
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 90
    @ScaledMetric(relativeTo: .body) private var maximumColumnWidth: CGFloat = 280

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
            MarkdownTableLayout(columns: table.header.count,
                                minimumWidth: minimumColumnWidth, maximumWidth: maximumColumnWidth) {
                let cells = ([table.header] + table.rows).flatMap { $0 }
                ForEach(Array(cells.enumerated()), id: \.offset) { index, text in
                    cell(text, alignment: table.alignments[index % table.header.count],
                         isHeader: index < table.header.count)
                }
            }.padding(12)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("message.attachment.markdown.table")
    }

    private func cell(_ text: String, alignment: MarkdownDocumentTable.Alignment,
                      isHeader: Bool) -> some View {
        Text(MessageMarkdown.inline(text))
            .fontWeight(isHeader ? .semibold : .regular)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: cellAlignment(alignment))
            .padding(.bottom, isHeader ? 8 : 0)
            .overlay(alignment: .bottom) { if isHeader { Divider() } }
    }

    private func cellAlignment(_ value: MarkdownDocumentTable.Alignment) -> Alignment {
        switch value { case .leading: .topLeading; case .center: .top; case .trailing: .topTrailing }
    }
}

private struct MarkdownTableLayout: Layout {
    let columns: Int
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    private let columnSpacing: CGFloat = 20
    private let rowSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(subviews)
        return CGSize(width: sizes.widths.reduce(0, +) + columnSpacing * CGFloat(columns - 1),
                      height: sizes.heights.reduce(0, +) + rowSpacing * CGFloat(sizes.heights.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(subviews)
        var y = bounds.minY
        for (row, height) in sizes.heights.enumerated() {
            var x = bounds.minX
            for (column, width) in sizes.widths.enumerated() {
                subviews[row * columns + column].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: width, height: height)
                )
                x += width + columnSpacing
            }
            y += height + rowSpacing
        }
    }

    private func measure(_ subviews: Subviews) -> (widths: [CGFloat], heights: [CGFloat]) {
        let widths = (0..<columns).map { column in
            let ideal = stride(from: column, to: subviews.count, by: columns).map {
                subviews[$0].sizeThatFits(.unspecified).width
            }.max() ?? minimumWidth
            return min(maximumWidth, max(minimumWidth, ideal))
        }
        let heights = (0..<(subviews.count / columns)).map { row in
            (0..<columns).map { column in
                subviews[row * columns + column].sizeThatFits(
                    ProposedViewSize(width: widths[column], height: nil)
                ).height
            }.max() ?? 0
        }
        return (widths, heights)
    }
}
