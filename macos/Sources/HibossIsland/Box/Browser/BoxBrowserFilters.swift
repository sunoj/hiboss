// Native kind and author menus that fit the toolbar, retaining project scoping.
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
        case .boss: L("Me")
        case .agents: L("Agents")
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
        Picker(L("Kind"), selection: $store.kind) {
            Text(L("All")).tag(nil as BoxItem.Kind?)
            ForEach(BoxItem.Kind.allCases, id: \.self) { kind in
                Text(kind.filterTitle).tag(Optional(kind))
            }
        }.pickerStyle(.menu).controlSize(.small).fixedSize()
            .accessibilityIdentifier("box.filters")
            .layoutProbe("box.filters")
    }

    var authorPicker: some View {
        Picker(L("Source:"), selection: $store.author) {
            ForEach(BoxAuthorFilter.allCases) { author in
                Text(L("Source:") + " " + author.title).tag(author)
            }
        }.pickerStyle(.menu).labelsHidden().controlSize(.small).fixedSize()
            .accessibilityIdentifier("box.source")
            .layoutProbe("box.source")
    }

    @ViewBuilder var projectPicker: some View {
        if let project = store.project {
            Menu {
                Button(L("All projects")) { store.project = nil }
            } label: { ProjectLabelView(slug: project) }
        }
    }

}
