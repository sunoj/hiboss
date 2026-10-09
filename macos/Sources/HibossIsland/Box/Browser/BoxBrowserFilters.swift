// Native filter chips for Box authors and kinds, retaining project scoping.
// Exports: BoxAuthorFilter and BoxBrowserFilters; author filters preserve paging.
// Dependencies: SwiftUI, HibossKit BoxItem, and BoxBrowserStore.

import HibossKit
import SwiftUI

enum BoxAuthorFilter: CaseIterable, Identifiable {
    case all, boss, agents
    var id: Self { self }
    var title: String {
        switch self {
        case .all: L("All")
        case .boss: L("From me")
        case .agents: L("From agents")
        }
    }
    func includes(_ item: BoxItem) -> Bool {
        switch self {
        case .all: true
        case .boss: item.author.isBoss
        case .agents: !item.author.isBoss
        }
    }
}

struct BoxBrowserFilters: View {
    @ObservedObject var store: BoxBrowserStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Box")).font(.title2.bold())
                if let project = store.project {
                    Text(project).font(.callout).foregroundStyle(TodayStyle.secondary)
                    Button(L("All projects")) { store.project = nil }
                }
                Spacer()
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(BoxAuthorFilter.allCases) { author in
                        chip(author.title, selected: store.author == author) { store.author = author }
                    }
                    Divider().frame(height: 20)
                    chip(L("All kinds"), selected: store.kind == nil) { store.kind = nil }
                    ForEach(BoxItem.Kind.allCases, id: \.self) { kind in
                        chip(kind.title, selected: store.kind == kind) { store.kind = kind }
                    }
                }.padding(.vertical, 2)
            }
        }.padding(20).background(TodayStyle.surface)
        .accessibilityIdentifier("box.filters")
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered)
            .tint(selected ? TodayStyle.ink : TodayStyle.tertiary)
            .accessibilityValue(selected ? L("Selected") : L("Not selected"))
    }
}
