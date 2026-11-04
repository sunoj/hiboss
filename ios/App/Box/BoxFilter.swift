// Independent search, author and kind filters for the Box browser and reference picker.
// Exports BoxFilter and BoxFilterChips; filters preserve the server's item order.
// Dependencies: SwiftUI, HibossKit BoxItem, and localized kind labels.

import HibossKit
import SwiftUI

enum BoxFilter: String, CaseIterable {
    case all, link, text, image, video, file

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .link: String(localized: "Links")
        case .text: String(localized: "Text")
        case .image: String(localized: "Images")
        case .video: String(localized: "Videos")
        case .file: String(localized: "Files")
        }
    }

    var isMedia: Bool { self == .image || self == .video }

    func matches(_ item: BoxItem, search: String, author: BoxAuthorFilter = .all,
                 liked: Bool = false) -> Bool {
        let kindMatches = self == .all || item.kind.rawValue == rawValue
        let terms = [item.text, item.url, item.note, item.project, item.provenanceLabel]
            .compactMap { $0 }.joined(separator: " ") + " " + item.tags.joined(separator: " ")
        return kindMatches && author.matches(item) && (!liked || item.liked) &&
            (search.isEmpty || terms.localizedCaseInsensitiveContains(search))
    }
}

enum BoxAuthorFilter: String, CaseIterable {
    case all, mine, agents

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .mine: String(localized: "Me")
        case .agents: String(localized: "Agents")
        }
    }

    func matches(_ item: BoxItem) -> Bool {
        self == .all || (self == .mine ? item.author.isBoss : !item.author.isBoss)
    }
}

enum BoxListStyle: String, CaseIterable {
    case list, cards

    var title: String {
        self == .list ? String(localized: "List") : String(localized: "Cards")
    }
}

struct BoxFilterChips: View {
    @Binding var selection: BoxFilter
    @Binding var liked: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.xs) {
                likedChip
                .frame(minWidth: ControlMetric.minTap, minHeight: ControlMetric.minTap)
                .accessibilityAddTraits(liked ? .isSelected : [])
                .accessibilityIdentifier("box-filter-liked")
                ForEach(BoxFilter.allCases, id: \.self) { filter in
                    chip(filter)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                    .accessibilityIdentifier("box-filter-\(filter.rawValue)")
                }
            }
            .padding(.horizontal, Space.m)
        }
        .defaultScrollAnchor(.leading)
        .scrollIndicators(.hidden)
        .padding(.vertical, Space.xs)
    }

    private var likedChip: some View {
        Button { liked.toggle() } label: {
            Label("Liked", systemImage: liked ? "heart.fill" : "heart")
                .modifier(BoxChipStyle(selected: liked))
        }.buttonStyle(.plain)
    }

    private func chip(_ filter: BoxFilter) -> some View {
        Button { selection = filter } label: {
            Text(verbatim: filter.title)
                .modifier(BoxChipStyle(selected: selection == filter))
        }.buttonStyle(.plain)
    }
}

private struct BoxChipStyle: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .foregroundStyle(selected ? Theme.onAccent : Theme.ink)
            .background(selected ? Theme.ink : Theme.surface2, in: Capsule())
            .frame(minWidth: ControlMetric.minTap, minHeight: ControlMetric.minTap)
            .contentShape(Rectangle())
    }
}
