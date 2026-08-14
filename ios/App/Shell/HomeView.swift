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
            .toolbarTitleMenu {
                Picker(selection: $section) {
                    Label("Inbox", systemImage: HomeSection.inbox.systemImage)
                        .tag(HomeSection.inbox)
                    Label("Messages", systemImage: HomeSection.messages.systemImage)
                        .tag(HomeSection.messages)
                } label: {
                    Text(section.title)
                }
            }
            .toolbar {
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
