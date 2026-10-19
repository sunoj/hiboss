// Mutable demo likes and collections, using the production API signatures.
// Provides live counts and covers so demo interactions exercise persistent actor state.
import Foundation
import HibossKit

extension DemoBoxAPI {
    func boxItem(id: String) async throws -> BoxItem {
        guard let item = items.first(where: { $0.id == id }) else {
            throw HibossAPIError.invalidResponse
        }
        return item
    }

    func boxCollections() async throws -> [BoxCollection] {
        collectionNames.map { id, name in
            let members = items.filter { $0.collectionIDs.contains(id) }
            return BoxCollection(id: id, bossID: "demo-boss", bossName: "Demo", name: name,
                                 itemCount: members.count,
                                 coverItemID: members.first { $0.kind == .image || $0.kind == .video }?.id,
                                 createdAt: "2026-10-01T00:00:00Z", updatedAt: "2026-10-01T00:00:00Z")
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func createBoxCollection(name: String) async throws -> BoxCollection {
        guard collectionNames.count < 200 else { throw HibossAPIError.invalidResponse }
        let clean = try validatedCollectionName(name)
        let id = UUID().uuidString
        collectionNames[id] = clean
        guard let created = try await boxCollections().first(where: { $0.id == id }) else {
            throw HibossAPIError.invalidResponse
        }
        return created
    }

    func renameBoxCollection(id: String, name: String) async throws -> BoxCollection {
        guard collectionNames[id] != nil else { throw HibossAPIError.invalidResponse }
        collectionNames[id] = try validatedCollectionName(name, excluding: id)
        guard let updated = try await boxCollections().first(where: { $0.id == id }) else {
            throw HibossAPIError.invalidResponse
        }
        return updated
    }

    func deleteBoxCollection(id: String) async throws {
        collectionNames[id] = nil
        items = items.map { $0.organized(collectionIDs: $0.collectionIDs.filter { $0 != id }) }
    }

    func setBoxItem(id: String, liked: Bool) async throws -> BoxItem {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            throw HibossAPIError.invalidResponse
        }
        if failsLikes {
            throw HibossAPIError.requestFailed(
                status: 503, message: String(localized: "Couldn't update Like"))
        }
        let previous = items[index]
        items[index] = previous.organized(liked: liked,
                                          likedAt: previous.likedAt ?? Date().ISO8601Format())
        return items[index]
    }

    func setBoxItem(id: String, inCollection: String, member: Bool) async throws -> BoxItem {
        guard let index = items.firstIndex(where: { $0.id == id }),
              collectionNames[inCollection] != nil else {
            throw HibossAPIError.invalidResponse
        }
        var ids = items[index].collectionIDs
        if member && !ids.contains(inCollection) { ids.append(inCollection) }
        if !member { ids.removeAll { $0 == inCollection } }
        items[index] = items[index].organized(collectionIDs: ids)
        return items[index]
    }

    private func validatedCollectionName(_ name: String, excluding: String? = nil) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 64,
              clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw HibossAPIError.requestFailed(
                status: 400, message: String(localized: "Enter 1–64 characters without control characters."))
        }
        guard !collectionNames.contains(where: {
            $0.key != excluding && $0.value.localizedCaseInsensitiveCompare(clean) == .orderedSame
        }) else {
            throw HibossAPIError.requestFailed(
                status: 409, message: String(localized: "Collection name already exists."))
        }
        return clean
    }
}
