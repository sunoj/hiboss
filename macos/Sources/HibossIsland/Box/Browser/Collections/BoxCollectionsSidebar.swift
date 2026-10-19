// Native Box scopes and named collections, including drop targets and management dialogs.
// Exports BoxCollectionsSidebar and a reusable collection name editor.

import HibossKit
import SwiftUI

struct BoxCollectionsSidebar: View {
    @ObservedObject var store: BoxBrowserStore
    var workspace: AnyView?
    @State private var creating = false
    @State private var renaming: BoxCollection?
    @State private var deleting: BoxCollection?

    var body: some View {
        VStack(spacing: 0) {
            if let workspace { workspace }
            List {
                Button { store.scope = .all } label: {
                    Label(L("All"), systemImage: "archivebox")
                }.listRowBackground(store.scope == .all ? Color.accentColor.opacity(0.15) : .clear)
                Button { store.scope = .liked } label: {
                    Label(L("Liked"), systemImage: "heart.fill")
                }.listRowBackground(store.scope == .liked ? Color.accentColor.opacity(0.15) : .clear)
                collectionSection
            }.listStyle(.sidebar).buttonStyle(.plain).frame(maxHeight: 280)
        }
        .sheet(isPresented: $creating) { BoxCollectionEditor(store: store) }
        .sheet(item: $renaming) { BoxCollectionEditor(store: store, collection: $0) }
        .alert(L("Delete Collection"), isPresented: Binding(get: { deleting != nil },
            set: { if !$0 { deleting = nil } })) {
            Button(L("Delete Collection"), role: .destructive) {
                if let collection = deleting { Task { await store.deleteCollection(collection) } }
                deleting = nil
            }
            Button(L("Cancel"), role: .cancel) { deleting = nil }
        } message: { Text(L("Items stay in your Box.")) }
    }

    private var collectionSection: some View {
        Section {
            ForEach(store.collections) { collection in
                Button { store.scope = .collection(collection.id) } label: {
                    HStack {
                        Label { Text(verbatim: collection.name) } icon: {
                            Image(systemName: "rectangle.stack")
                        }
                        Spacer()
                        Text(collection.itemCount.formatted()).foregroundStyle(.secondary)
                    }
                }
                .layoutProbe("box.collection.\(collection.id)")
                .listRowBackground(store.scope == .collection(collection.id)
                    ? Color.accentColor.opacity(0.15) : .clear)
                .dropDestination(for: String.self) { ids, _ in
                    let items = store.items.filter { ids.contains($0.id) && $0.bossID == collection.bossID }
                    for item in items {
                        Task { await store.setMembership(item, collection: collection.id, member: true) }
                    }
                    return !items.isEmpty
                }
                .contextMenu {
                    Button(L("Rename")) { renaming = collection }
                    Button(L("Delete Collection"), role: .destructive) { deleting = collection }
                }
            }
        } header: {
            HStack {
                Text(L("Collections"))
                Spacer()
                Button { creating = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).accessibilityLabel(L("Box New Collection"))
            }
        }
    }
}

struct BoxCollectionEditor: View {
    @ObservedObject var store: BoxBrowserStore
    var collection: BoxCollection? = nil
    var item: BoxItem? = nil
    @State private var name = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(collection == nil ? L("Box New Collection") : L("Rename")).font(.headline)
            TextField(L("Collection name"), text: $name)
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save")) {
                    saving = true
                    Task {
                        if await store.saveCollection(name: name, id: collection?.id, item: item) {
                            dismiss()
                        }
                        saving = false
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
            if let error = store.actionError { Text(verbatim: error).foregroundStyle(.red) }
        }.padding(20).frame(width: 340)
            .onAppear { name = collection?.name ?? "" }
    }
}
