// Collection and like operations used by the native Box surfaces.
// Exports an app service boundary backed by the existing HibossKit API.
import HibossKit

protocol BoxCollectionServing: BoxServing {
    func boxItem(id: String) async throws -> BoxItem
    func boxCollections() async throws -> [BoxCollection]
    func createBoxCollection(name: String) async throws -> BoxCollection
    func renameBoxCollection(id: String, name: String) async throws -> BoxCollection
    func deleteBoxCollection(id: String) async throws
    func setBoxItem(id: String, liked: Bool) async throws -> BoxItem
    func setBoxItem(id: String, inCollection: String, member: Bool) async throws -> BoxItem
}

extension HibossAPI: BoxCollectionServing {}
