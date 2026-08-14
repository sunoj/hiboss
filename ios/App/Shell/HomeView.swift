// Home tab root: switches Inbox (decision queue) and Messages (flat history).
// Exports: HomeSection, HomeView bound to InboxStore.
// Dependencies: SwiftUI, InboxView, MessagesView, ConnectionDot.

import SwiftUI

enum HomeSection: String, CaseIterable, Hashable {
    case inbox
    case messages

    var title: String {
        switch self {
        case .inbox: String(localized: "Inbox")
        case .messages: String(localized: "Messages")
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray.full"
        case .messages: "bubble.left.and.bubble.right"
        }
    }
}

struct HomeView: View {
    @ObservedObject var store: InboxStore
    @Binding var section: HomeSection

    var body: some View {
        content
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sits in the title position so both sides stay visible and one tap
                // apart, without spending a row of the queue's vertical space.
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $section) {
                        ForEach(HomeSection.allCases, id: \.self) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionDot(state: store.connectionState)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .inbox:
            InboxView(store: store)
        case .messages:
            MessagesView(store: store)
        }
    }
}
