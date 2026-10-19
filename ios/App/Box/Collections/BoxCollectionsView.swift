// Collection grid with live covers, scoped Box navigation and confirmed deletion.
// Uses system menus, forms and semantic colors for accessible native presentation.
import HibossKit
import SwiftUI

struct BoxCollectionsView: View {
    @ObservedObject var store: BoxStore
    @ObservedObject var media: BoxMediaStore
    @State private var creating = false
    @State private var editing: BoxCollection?
    @State private var deleting: BoxCollection?

    var body: some View {
        ScrollView {
            BoxOrganizationError(store: store).padding(.horizontal)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(store.collections) { collection in
                    NavigationLink {
                        BoxCollectionList(store: store, collection: collection)
                    } label: { tile(collection) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("box-collection-\(collection.id)")
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { editing = collection }
                        Button("Delete Collection", systemImage: "trash", role: .destructive) {
                            deleting = collection
                        }
                    }
                }
            }.padding()
        }
        .navigationTitle("Collections")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Collection", systemImage: "plus") { creating = true }
            }
        }
        .task { await store.loadCollections() }
        .sheet(isPresented: $creating) { BoxCollectionEditor(store: store) }
        .sheet(item: $editing) { BoxCollectionEditor(store: store, existing: $0) }
        .alert("Delete Collection", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete Collection", role: .destructive) {
                if let deleting { Task { await store.deleteCollection(deleting) } }
                deleting = nil
            }
        } message: {
            Text("Delete this collection? Items stay in the Box.")
            if let deleting { Text(verbatim: deleting.name) }
        }
        .accessibilityIdentifier("box-collections-grid")
    }

    private func tile(_ collection: BoxCollection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let coverID = collection.coverItemID {
                BoxCollectionCover(id: coverID, api: store.api, media: media).frame(height: 140)
            } else {
                Image(systemName: "rectangle.stack").font(.largeTitle)
                    .frame(maxWidth: .infinity).frame(height: 140)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            Text(verbatim: collection.name).font(.headline)
            Text(collection.itemCount, format: .number).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BoxCollectionList: View {
    @ObservedObject var store: BoxStore
    let collection: BoxCollection
    @State private var editing = false
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss

    private var current: BoxCollection {
        store.collections.first { $0.id == collection.id } ?? collection
    }

    var body: some View {
        BoxListView(api: store.api, collectionID: collection.id)
            .navigationTitle(Text(verbatim: current.name))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rename", systemImage: "pencil") { editing = true }
                        Button("Delete Collection", systemImage: "trash", role: .destructive) {
                            deleting = true
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityIdentifier("box-collection-menu")
                }
            }
            .sheet(isPresented: $editing) { BoxCollectionEditor(store: store, existing: current) }
            .alert("Delete Collection", isPresented: $deleting) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Collection", role: .destructive) {
                    Task { await store.deleteCollection(current) }
                }
            } message: {
                Text("Delete this collection? Items stay in the Box.")
                Text(verbatim: current.name)
            }
            .onChange(of: store.collections.map(\.id)) { _, ids in
                if !ids.contains(collection.id) { dismiss() }
            }
    }
}
