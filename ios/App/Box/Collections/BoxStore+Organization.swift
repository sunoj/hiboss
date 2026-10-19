// Like rollback and collection mutations for the Box browser.
// Updates the shared item state and surfaces failures inline without automatic retries.
import Foundation
import HibossKit

extension BoxStore {
    func loadCollections() async {
        guard let api = api as? any BoxCollectionServing else { return }
        do {
            collections = try await api.boxCollections()
            organizationError = nil
        } catch { organizationError = error.localizedDescription }
    }

    func toggleLike(_ original: BoxItem) async {
        guard let api = api as? any BoxCollectionServing,
              !organizing.contains(original.id),
              let index = items.firstIndex(where: { $0.id == original.id }) else { return }
        let previous = items[index]
        organizing.insert(previous.id)
        organizationError = nil
        items[index] = previous.organized(liked: !previous.liked,
                                         likedAt: Date().ISO8601Format())
        defer { organizing.remove(previous.id) }
        do {
            let updated = try await api.setBoxItem(id: previous.id, liked: !previous.liked)
            if let index = items.firstIndex(where: { $0.id == previous.id }) { items[index] = updated }
        } catch {
            if let index = items.firstIndex(where: { $0.id == previous.id }) { items[index] = previous }
            organizationError = error.localizedDescription
        }
    }

    func setMembership(_ item: BoxItem, collection: BoxCollection, member: Bool) async {
        guard let api = api as? any BoxCollectionServing, !organizing.contains(item.id) else { return }
        organizing.insert(item.id)
        organizationError = nil
        defer { organizing.remove(item.id) }
        do {
            let updated = try await api.setBoxItem(id: item.id, inCollection: collection.id, member: member)
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = updated }
            await loadCollections()
        } catch { organizationError = error.localizedDescription }
    }

    func saveCollection(name: String, existing: BoxCollection? = nil) async -> Bool {
        guard let api = api as? any BoxCollectionServing else { return false }
        organizationError = nil
        do {
            if let existing { _ = try await api.renameBoxCollection(id: existing.id, name: name) }
            else { _ = try await api.createBoxCollection(name: name) }
            await loadCollections()
            return true
        } catch {
            organizationError = error.localizedDescription
            return false
        }
    }

    func deleteCollection(_ collection: BoxCollection) async {
        guard let api = api as? any BoxCollectionServing else { return }
        organizationError = nil
        do {
            try await api.deleteBoxCollection(id: collection.id)
            items = items.map { $0.organized(collectionIDs: $0.collectionIDs.filter { $0 != collection.id }) }
            await loadCollections()
        } catch { organizationError = error.localizedDescription }
    }
}
