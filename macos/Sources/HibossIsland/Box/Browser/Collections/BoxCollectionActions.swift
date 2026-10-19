// Shared native like and collection actions for the detail pane and row context menus.
// Uses BoxBrowserStore and HibossKit membership identifiers.

import HibossKit
import SwiftUI

struct BoxCollectionActions: View {
    @ObservedObject var store: BoxBrowserStore
    let item: BoxItem
    var keyboardShortcutEnabled = false

    var body: some View {
        Button {
            Task { await store.toggleLike(item) }
        } label: {
            Label(item.liked ? L("Unlike") : L("Like"), systemImage: item.liked ? "heart.fill" : "heart")
        }.disabled(store.mutating.contains(item.id))
        .keyboardShortcut(keyboardShortcutEnabled ? KeyboardShortcut("l", modifiers: .command) : nil)
        .layoutProbe("box.like.\(item.id)")
        Menu {
            ForEach(store.collections.filter { $0.bossID == item.bossID }) { collection in
                Toggle(collection.name, isOn: Binding(
                    get: { item.collectionIDs.contains(collection.id) },
                    set: { member in
                        Task { await store.setMembership(item, collection: collection.id, member: member) }
                    }))
            }
            Divider()
            Button(L("New Collection…")) {
                store.newCollectionItem = item
                store.creatingCollection = true
            }
        } label: { Label(L("Add to Collection…"), systemImage: "rectangle.stack") }
        .disabled(store.mutating.contains(item.id))
    }
}
