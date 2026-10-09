// Paged Box reads with server-side search, superseding filters and confirmed deletion.
// Exports: BoxBrowserStore and the macOS BoxBrowsing service boundary.
// Dependencies: Combine, HibossKit and localized app strings.

import Combine
import Foundation
import HibossKit

protocol BoxBrowsing: BoxServing {
    func searchBoxItems(
        query: String, filters: BoxFilters, limit: Int, cursor: String?
    ) async throws -> BoxPage
}

extension HibossAPI: BoxBrowsing {}

@MainActor
final class BoxBrowserStore: ObservableObject {
    typealias Provider = @MainActor () -> (any BoxBrowsing)?
    @Published private(set) var items: [BoxItem] = []
    @Published private(set) var didLoad = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPaging = false
    @Published private(set) var error: String?
    @Published private(set) var pageError: String?
    @Published private(set) var nextCursor: String?
    @Published private(set) var deleting: Set<String> = []
    @Published var actionError: String?
    @Published var kind: BoxItem.Kind? { didSet { if kind != oldValue { invalidateRead() } } }
    @Published var query = "" { didSet { if query != oldValue { invalidateRead() } } }
    let apiProvider: Provider
    private var generation = 0
    private var connectionGeneration = 0
    private var deleted: Set<String> = []

    init(apiProvider: @escaping Provider) { self.apiProvider = apiProvider }

    func reset() {
        generation += 1
        connectionGeneration += 1
        items = []
        deleted = []
        deleting = []
        didLoad = false
        isLoading = false
        isPaging = false
        error = nil
        pageError = nil
        actionError = nil
        nextCursor = nil
    }

    private func invalidateRead() {
        generation += 1
        nextCursor = nil
        pageError = nil
        isPaging = false
    }

    func refresh() async {
        generation += 1
        let current = generation
        isLoading = true
        isPaging = false
        nextCursor = nil
        pageError = nil
        await fetch(cursor: nil, generation: current)
        if current == generation { isLoading = false }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoading, !isPaging else { return }
        let current = generation
        isPaging = true
        await fetch(cursor: cursor, generation: current)
        if current == generation { isPaging = false }
    }

    private func fetch(cursor: String?, generation current: Int) async {
        do {
            guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
            let filters = BoxFilters(kind: kind)
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = try await query.isEmpty
                ? api.boxItems(filters: filters, limit: 20, cursor: cursor)
                : api.searchBoxItems(query: query, filters: filters, limit: 20, cursor: cursor)
            guard current == generation, !Task.isCancelled else { return }
            var ids = cursor == nil ? Set<String>() : Set(items.map(\.id))
            let rows = page.items.filter { !deleted.contains($0.id) && ids.insert($0.id).inserted }
            items = (cursor == nil ? rows : items + rows).sorted {
                (ISODate.parse($0.createdAt) ?? .distantPast) > (ISODate.parse($1.createdAt) ?? .distantPast)
            }
            nextCursor = page.nextCursor
            error = nil
            pageError = nil
            didLoad = true
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            if cursor == nil { self.error = error.localizedDescription }
            else { pageError = error.localizedDescription }
            didLoad = true
        }
    }

    func delete(_ item: BoxItem) async -> Bool {
        guard let api = apiProvider(), !deleting.contains(item.id) else { return false }
        let current = connectionGeneration
        deleting.insert(item.id)
        defer { if current == connectionGeneration { deleting.remove(item.id) } }
        do {
            try await api.deleteBoxItem(id: item.id, purge: false)
            guard current == connectionGeneration else { return false }
            deleted.insert(item.id)
            items.removeAll { $0.id == item.id }
            return true
        } catch {
            if current == connectionGeneration { actionError = error.localizedDescription }
            return false
        }
    }
}

enum BoxBrowserError: LocalizedError {
    case notConfigured, cannotOpen
    case media(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: L("Connect to HiBoss to browse your Box.")
        case .cannotOpen: L("Couldn't open this item.")
        case let .media(message): message
        }
    }
}
