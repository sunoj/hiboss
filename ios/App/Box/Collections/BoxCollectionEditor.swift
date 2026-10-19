// Native collection name editor with server validation errors kept visible.
// Used for both creation and rename; depends on BoxStore.
import HibossKit
import SwiftUI

struct BoxCollectionEditor: View {
    @ObservedObject var store: BoxStore
    var existing: BoxCollection?
    var adding: BoxItem?
    @State private var name = ""
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Collection name", text: $name)
                    .accessibilityIdentifier("box-collection-name")
                BoxOrganizationError(store: store)
            }
            .navigationTitle(existing == nil
                             ? String(localized: "New Collection") : String(localized: "Rename"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            if await store.saveCollection(name: name, existing: existing, adding: adding) { dismiss() }
                            saving = false
                        }
                    }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.onAppear { name = existing?.name ?? "" }
    }
}
