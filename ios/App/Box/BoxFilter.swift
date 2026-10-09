// Search and author/kind filters shared by the Box grid and reference picker.
// Exports BoxFilter and BoxFilterChips; filters preserve the server's item order.
// Dependencies: SwiftUI, HibossKit BoxItem, and localized kind labels.

import HibossKit
import SwiftUI

enum BoxFilter: String, CaseIterable {
    case all, mine, agents, link, text, image, video, file

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .mine: String(localized: "From me")
        case .agents: String(localized: "From agents")
        case .link: String(localized: "Link")
        case .text: String(localized: "Text")
        case .image: String(localized: "Image")
        case .video: String(localized: "Video")
        case .file: String(localized: "File")
        }
    }

    func matches(_ item: BoxItem, search: String) -> Bool {
        let kindMatches: Bool
        switch self {
        case .all: kindMatches = true
        case .mine: kindMatches = item.author.isBoss
        case .agents: kindMatches = !item.author.isBoss
        default: kindMatches = item.kind.rawValue == rawValue
        }
        let terms = [item.text, item.url, item.note, item.project, item.provenanceLabel]
            .compactMap { $0 }.joined(separator: " ") + " " + item.tags.joined(separator: " ")
        return kindMatches && (search.isEmpty || terms.localizedCaseInsensitiveContains(search))
    }
}

struct BoxFilterChips: View {
    @Binding var selection: BoxFilter

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(BoxFilter.allCases, id: \.self) { filter in
                    chip(filter)
                    .accessibilityAddTraits(selection == filter ? .isSelected : [])
                    .accessibilityIdentifier("box-filter-\(filter.rawValue)")
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func chip(_ filter: BoxFilter) -> some View {
        let button = Button { selection = filter } label: {
            Text(verbatim: filter.title).font(.subheadline).frame(minHeight: 44)
        }
        if selection == filter {
            button.prominentAction().tint(Theme.primaryAction)
        } else {
            button.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(Theme.ink2)
        }
    }
}
