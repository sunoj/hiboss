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
                            .listRowInsets(EdgeInsets(top: Space.s, leading: Space.m,
                                                     bottom: Space.s, trailing: Space.m))
                    } header: { Text(verbatim: group.title).hbSectionHeader() }
                }
            }
            footer()
        }.listStyle(.insetGrouped)
            .contentMargins(.horizontal, Space.m, for: .scrollContent)
    }

    private var grid: some View {
        List {
            ForEach(BoxDayGroup.allCases, id: \.self) { group in
                let matches = items.filter { BoxDayGroup.group($0) == group }
                if !matches.isEmpty {
                    Section {
                        LazyVGrid(columns: Array(
                            repeating: GridItem(.flexible(), spacing: Space.xs, alignment: .top),
                            count: filter.isMedia ? 3 : 2
                        ), spacing: Space.xs) {
                            ForEach(matches) { item in
                                row(item)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .frame(height: filter.isMedia ? nil
                                           : (textSize.isAccessibilitySize ? 460 : 260), alignment: .top)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: .zero))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } header: { Text(verbatim: group.title).hbSectionHeader() }
                }
            }
            footer()
        }.listStyle(.insetGrouped)
            .contentMargins(.horizontal, Space.m, for: .scrollContent)
    }
}
