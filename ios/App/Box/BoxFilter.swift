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
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(BoxFilter.allCases, id: \.self) { filter in
                    chip(filter)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                    .accessibilityIdentifier("box-filter-\(filter.rawValue)")
                }
                Button { liked.toggle() } label: {
                    Label("Liked", systemImage: "heart.fill").font(.subheadline)
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .tint(liked ? Theme.primaryAction : Theme.ink2)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityAddTraits(liked ? .isSelected : [])
                .accessibilityIdentifier("box-filter-liked")
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .frame(height: textSize.isAccessibilitySize ? 88 : 64)
    }

    @ViewBuilder private func chip(_ filter: BoxFilter) -> some View {
        let button = Button { selection = filter } label: {
            Text(verbatim: filter.title).font(.subheadline)
        }
        if selection == filter {
            button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(.small).tint(Theme.primaryAction)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        } else {
            button.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Theme.ink2)
                .controlSize(.small)
                .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
    }
}
