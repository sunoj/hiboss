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
        case .mine: String(localized: "From me")
        case .agents: String(localized: "From agents")
        }
    }

    func matches(_ item: BoxItem) -> Bool {
        self == .all || (self == .mine ? item.author.isBoss : !item.author.isBoss)
    }
}

struct BoxFilterChips: View {
    @Binding var selection: BoxFilter
    @Binding var author: BoxAuthorFilter
    @Binding var liked: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.xs) {
                chip(.all)
                ForEach([BoxAuthorFilter.mine, .agents], id: \.self) { option in authorChip(option) }
                ForEach([BoxFilter.image, .link, .text, .file, .video], id: \.self) { option in
                    chip(option)
                }
                likedChip
                    .accessibilityAddTraits(liked ? .isSelected : [])
                    .accessibilityIdentifier("box-filter-liked")
            }
            .padding(.horizontal, Space.m)
        }
        .defaultScrollAnchor(.leading)
        .scrollIndicators(.hidden)
        .padding(.vertical, Space.xs)
        .accessibilityIdentifier("box-filters")
    }

    private var likedChip: some View {
        Button { liked.toggle() } label: {
            Label("Liked", systemImage: liked ? "heart.fill" : "heart")
                .modifier(BoxChipStyle(selected: liked))
        }.buttonStyle(.plain)
    }

    private func chip(_ filter: BoxFilter) -> some View {
        let selected = selection == filter && (filter != .all || author == .all && !liked)
        return Button {
            selection = filter
            if filter == .all {
                author = .all
                liked = false
            }
        } label: {
            Text(verbatim: filter.title)
                .modifier(BoxChipStyle(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("box-filter-\(filter.rawValue)")
    }

    private func authorChip(_ option: BoxAuthorFilter) -> some View {
        Button { author = author == option ? .all : option } label: {
            Text(verbatim: option.title)
                .modifier(BoxChipStyle(selected: author == option))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(author == option ? .isSelected : [])
        .accessibilityIdentifier("box-author-\(option.rawValue)")
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
