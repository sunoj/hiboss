// Immediate membership checklist for a single Box item.
// Shares collection creation and errors with the grid through BoxStore.
import HibossKit
import SwiftUI

struct BoxCollectionSheet: View {
    let original: BoxItem
    @ObservedObject var store: BoxStore
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss

    private var item: BoxItem { store.items.first { $0.id == original.id } ?? original }

    var body: some View {
        NavigationStack {
            List {
                BoxOrganizationError(store: store)
                ForEach(store.collections.filter { $0.bossID == item.bossID }) { collection in
                    let member = item.collectionIDs.contains(collection.id)
                    Button {
                        Task { await store.setMembership(item, collection: collection, member: !member) }
                    } label: {
                        HStack {
                            Text(verbatim: collection.name).foregroundStyle(.primary)
                            Spacer()
                            if member { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .accessibilityAddTraits(member ? .isSelected : [])
                    .disabled(store.organizing.contains(item.id))
                    .accessibilityIdentifier("box-membership-\(collection.id)")
                }
                Button("New Collection", systemImage: "plus") { creating = true }
            }
            .navigationTitle("Add to Collection…")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $creating) { BoxCollectionEditor(store: store) }
            .task { await store.loadCollections() }
        }.accessibilityIdentifier("box-collection-sheet")
    }
}
