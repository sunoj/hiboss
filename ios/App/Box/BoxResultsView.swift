// Native sectioned grid for Box results, with one column at accessibility text sizes.
// Exports BoxResultsView, with recency grouping and pagination.
// Dependencies: SwiftUI, HibossKit and BoxDayGroup.

import HibossKit
import SwiftUI

struct BoxResultsView<Header: View, Row: View, Footer: View>: View {
    let items: [BoxItem]
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (BoxItem) -> Row
    @ViewBuilder let footer: () -> Footer
    @Environment(\.dynamicTypeSize) private var textSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Space.s, alignment: .top),
              count: textSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.m) {
                header()
                ForEach(BoxDayGroup.allCases, id: \.self) { group in
                    let matches = items.filter { BoxDayGroup.group($0) == group }
                    if !matches.isEmpty {
                        Section {
                            LazyVGrid(columns: columns, spacing: Space.s) {
                                ForEach(matches) { row($0) }
                            }
                        } header: {
                            Text(verbatim: group.title).font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                footer()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
        }
        .accessibilityIdentifier("box-grid")
    }
}
