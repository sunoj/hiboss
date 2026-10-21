// Native sectioned list and square media/content grids for filtered Box results.
// Exports BoxResultsView, keeping recency headers identical across display styles.
// Dependencies: SwiftUI, HibossKit and BoxDayGroup.

import HibossKit
import SwiftUI

struct BoxResultsView<Row: View, Footer: View>: View {
    let items: [BoxItem]
    let filter: BoxFilter
    let style: BoxListStyle
    @ViewBuilder let row: (BoxItem) -> Row
    @ViewBuilder let footer: () -> Footer
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Group {
            if filter.isMedia || style == .cards { grid } else { list }
        }.accessibilityIdentifier(filter.isMedia ? "box-photo-grid" : "box-\(style.rawValue)")
    }

    private var list: some View {
        List {
            ForEach(BoxDayGroup.allCases, id: \.self) { group in
                let matches = items.filter { BoxDayGroup.group($0) == group }
                if !matches.isEmpty {
                    Section {
                        ForEach(matches) { row($0) }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    } header: { Text(verbatim: group.title) }
                }
            }
            footer()
        }.listStyle(.insetGrouped)
    }

    private var grid: some View {
        List {
            ForEach(BoxDayGroup.allCases, id: \.self) { group in
                let matches = items.filter { BoxDayGroup.group($0) == group }
                if !matches.isEmpty {
                    Section {
                        LazyVGrid(columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
                            count: filter.isMedia ? 3 : 2
                        ), spacing: 8) {
                            ForEach(matches) { item in
                                row(item)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .frame(height: filter.isMedia ? nil
                                           : (textSize.isAccessibilitySize ? 460 : 260), alignment: .top)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } header: { Text(verbatim: group.title) }
                }
            }
            footer()
        }.listStyle(.insetGrouped)
    }
}
