// Collection service boundary and browser mutations with connection-scoped responses.
// Extends BoxBrowserStore; uses the existing HibossKit collection API.

import Foundation
import HibossKit

protocol BoxCollectionServing: Sendable {
    func boxCollections() async throws -> [BoxCollection]
    func createBoxCollection(name: String) async throws -> BoxCollection
    func renameBoxCollection(id: String, name: String) async throws -> BoxCollection
    func deleteBoxCollection(id: String) async throws
    func setBoxItem(id: String, liked: Bool) async throws -> BoxItem
    func setBoxItem(id: String, inCollection: String, member: Bool) async throws -> BoxItem
}

enum BoxBrowserScope: Equatable {
    case all, liked, collection(String)
    var collectionID: String? {
        if case let .collection(id) = self { return id }
        return nil
    }
}

extension BoxBrowserStore {
    func refreshCollections() async {
        let current = connectionGeneration
        do {
            guard let api = apiProvider() else { return }
            let result = try await api.boxCollections()
            guard current == connectionGeneration else { return }
            collections = result
        } catch {
            if current == connectionGeneration { actionError = error.localizedDescription }
        }
    }

    func saveCollection(name: String, id: String? = nil, item: BoxItem? = nil) async -> Bool {
        let current = connectionGeneration
        do {
            guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let collection: BoxCollection
            if let id { collection = try await api.renameBoxCollection(id: id, name: name) }
            else { collection = try await api.createBoxCollection(name: name) }
            guard current == connectionGeneration else { return false }
            await refreshCollections()
            if let item { await setMembership(item, collection: collection.id, member: true) }
            return true
        } catch {
            if current == connectionGeneration { actionError = error.localizedDescription }
            return false
        }
    }

    func deleteCollection(_ collection: BoxCollection) async {
        let current = connectionGeneration
        do {
            guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
            try await api.deleteBoxCollection(id: collection.id)
            guard current == connectionGeneration else { return }
            if scope == .collection(collection.id) { scope = .all }
            await refreshCollections()
        } catch {
            if current == connectionGeneration { actionError = error.localizedDescription }
        }
    }

    func toggleLike(_ item: BoxItem) async {
        await mutateItem(id: item.id) { try await $0.setBoxItem(id: item.id, liked: !item.liked) }
    }

    func setMembership(_ item: BoxItem, collection: String, member: Bool) async {
        let current = connectionGeneration
        await mutateItem(id: item.id) {
            try await $0.setBoxItem(id: item.id, inCollection: collection, member: member)
        }
        guard current == connectionGeneration else { return }
        await refreshCollections()
    }

    func mutateItem(id: String, _ operation: (any BoxBrowsing) async throws -> BoxItem) async {
        guard !mutating.contains(id) else { return }
        let current = connectionGeneration
        mutating.insert(id)
        defer { if current == connectionGeneration { mutating.remove(id) } }
        do {
            guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
            let item = try await operation(api)
            guard current == connectionGeneration else { return }
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
            if let id = scope.collectionID, !item.collectionIDs.contains(id) {
                items.removeAll { $0.id == item.id }
            }
            reconcileSelection()
        } catch {
            if current == connectionGeneration { actionError = error.localizedDescription }
        }
    }
}
