// Synthetic collection records and mutable service operations for Box feature tests.
// Extends ScriptedBoxBrowser without contacting a live service.

import Foundation
import HibossKit
@testable import HibossIsland

enum BoxCollectionFixtures {
    static let collections = ["design", "research"].map {
        BoxCollection(id: $0, bossID: "test-boss", bossName: "Test Boss",
            name: $0.capitalized, itemCount: $0 == "design" ? 1 : 0,
            createdAt: "2026-10-09T08:30:00Z", updatedAt: "2026-10-09T08:30:00Z")
    }
}

extension ScriptedBoxBrowser {
    func boxCollections() async throws -> [BoxCollection] { collections }

    func createBoxCollection(name: String) async throws -> BoxCollection {
        if failMutation { throw TestError.rejected }
        let collection = BoxCollection(id: name, bossID: "test-boss", bossName: "Test Boss",
            name: name, itemCount: 0, createdAt: "2026-10-09T08:30:00Z", updatedAt: "2026-10-09T08:30:00Z")
        collections.append(collection)
        return collection
    }

    func renameBoxCollection(id: String, name: String) async throws -> BoxCollection {
        if failMutation { throw TestError.rejected }
        collections.removeAll { $0.id == id }
        let collection = BoxCollection(id: id, bossID: "test-boss", bossName: "Test Boss",
            name: name, itemCount: 0, createdAt: "2026-10-09T08:30:00Z", updatedAt: "2026-10-09T08:30:00Z")
        collections.append(collection)
        return collection
    }

    func deleteBoxCollection(id: String) async throws {
        if failMutation { throw TestError.rejected }
        collections.removeAll { $0.id == id }
    }

    func setMutationFailure(_ fails: Bool) { failMutation = fails }

    func setBoxItem(id: String, liked: Bool) async throws -> BoxItem {
        try changeItem(id: id, values: ["liked": liked])
    }

    func setBoxItem(id: String, inCollection: String, member: Bool) async throws -> BoxItem {
        let item = pages.flatMap(\.items).first { $0.id == id }
        var ids = item?.collectionIDs ?? []
        ids.removeAll { $0 == inCollection }
        if member { ids.append(inCollection) }
        return try changeItem(id: id, values: ["collection_ids": ids])
    }

    func changeItem(id: String, values: [String: Any]) throws -> BoxItem {
        if failMutation { throw TestError.rejected }
        let original = pages.flatMap(\.items).first { $0.id == id } ?? BoxBrowserFixtures.item(id)
        let data = try JSONEncoder().encode(original)
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        json.merge(values) { _, new in new }
        let item = try JSONDecoder().decode(BoxItem.self, from: JSONSerialization.data(withJSONObject: json))
        pages = pages.map { page in
            BoxPage(items: page.items.map { $0.id == id ? item : $0 }, nextCursor: page.nextCursor)
        }
        return item
    }
}
