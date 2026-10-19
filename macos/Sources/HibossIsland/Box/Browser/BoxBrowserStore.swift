// Paged Box reads with server-side search, superseding filters and confirmed deletion.
// Exports: BoxBrowserStore and the macOS BoxBrowsing service boundary.
// Dependencies: Combine, HibossKit and localized app strings.

import Combine
import Foundation
import HibossKit

protocol BoxBrowsing: BoxServing, BoxCollectionServing {
    func patchBoxItem(id: String, patch: BoxPatch) async throws -> BoxItem
    func searchBoxItems(
        query: String, filters: BoxFilters, limit: Int, cursor: String?
    ) async throws -> BoxPage
}

extension HibossAPI: BoxBrowsing {}

@MainActor
final class BoxBrowserStore: ObservableObject {
    typealias Provider = @MainActor () -> (any BoxBrowsing)?
    @Published var items: [BoxItem] = []
    @Published private(set) var didLoad = false
    @Published private(set) var hasResult = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPaging = false
    @Published private(set) var error: String?
    @Published private(set) var pageError: String?
    @Published private(set) var nextCursor: String?
    @Published private(set) var deleting: Set<String> = []
    @Published var mutating: Set<String> = []
    @Published var collections: [BoxCollection] = []
    @Published var scope: BoxBrowserScope = .all { didSet { if scope != oldValue { invalidateRead() } } }
    @Published var creatingCollection = false
    @Published var newCollectionItem: BoxItem?
    @Published var actionError: String?
    @Published var selection: String?
    @Published var pendingDelete: BoxItem?
    @Published var author: BoxAuthorFilter = .all { didSet { reconcileSelection() } }
    @Published var project: String? { didSet { if project != oldValue { invalidateRead() } } }
    var visibleItems: [BoxItem] {
        items.filter { author.includes($0) && (kind == nil || $0.kind == kind)
            && (scope != .liked || $0.liked) }
    }
    var selectedItem: BoxItem? { visibleItems.first { $0.id == selection } }
    @Published var kind: BoxItem.Kind? { didSet { if kind != oldValue { invalidateRead() } } }
    @Published var query = "" { didSet { if query != oldValue { invalidateRead() } } }
    let apiProvider: Provider
    private var generation = 0
    var connectionGeneration = 0
    private var deleted: Set<String> = []
    private var loadedPages = 0

    private var authorizationObservation: AnyCancellable?

    init(apiProvider: @escaping Provider) {
        self.apiProvider = apiProvider
        authorizationObservation = AccountAuthorization.shared.observe { [weak self] _ in
            self?.reset()
        }
    }

    func reset() {
        collections = []
        mutating = []
        creatingCollection = false
        newCollectionItem = nil
        scope = .all
        selection = nil
        pendingDelete = nil
        generation += 1
        connectionGeneration += 1
        items = []
        deleted = []
        deleting = []
        didLoad = false
        hasResult = false
        loadedPages = 0
        isLoading = false
        isPaging = false
        error = nil
        pageError = nil
        actionError = nil
        nextCursor = nil
        wantsMoreAfterRefresh = false
    }

    private func invalidateRead() {
        selection = nil
        wantsMoreAfterRefresh = false
        generation += 1
        nextCursor = nil
        pageError = nil
        isPaging = false
        loadedPages = 0
    }

    func refresh() async {
        generation += 1
        let current = generation
        isLoading = true
        await fetch(cursor: nil, generation: current, pageCount: max(1, loadedPages))
        guard current == generation else { return }
        await refreshCollections()
        guard current == generation else { return }
        isLoading = false
        isPaging = false
        if wantsMoreAfterRefresh {
            wantsMoreAfterRefresh = false
            await loadMore()
        }
    }

    /// A "Load more" pressed during a refresh runs once the refresh has applied its result.
    private var wantsMoreAfterRefresh = false

    func loadMore() async {
        if isLoading { wantsMoreAfterRefresh = true; return }
        guard let cursor = nextCursor, !isPaging else { return }
        let current = generation
        isPaging = true
        await fetch(cursor: cursor, generation: current)
        if current == generation { isPaging = false }
    }

    private func readPage(cursor: String?) async throws -> BoxPage {
        guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
        let filters = BoxFilters(kind: kind, project: project, liked: scope == .liked, collection: scope.collectionID)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await query.isEmpty
            ? api.boxItems(filters: filters, limit: 20, cursor: cursor)
            : api.searchBoxItems(query: query, filters: filters, limit: 20, cursor: cursor)
    }

    private func fetch(cursor: String?, generation current: Int, pageCount: Int = 1) async {
        do {
            let boundary = cursor == nil && loadedPages > 0 ? items.min {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
            } : nil
            var fetched: [BoxItem] = []
            var next = cursor
            var count = 0
            while true {
                let page = try await readPage(cursor: next)
                guard current == generation, !Task.isCancelled else { return }
                fetched += page.items
                count += 1
                next = page.nextCursor
                let reachedBoundary = boundary.map { boundary in
                    fetched.contains {
                        $0.createdAt < boundary.createdAt
                            || ($0.createdAt == boundary.createdAt && $0.id <= boundary.id)
                    }
                } ?? true
                if next == nil || (count >= pageCount && reachedBoundary) { break }
            }
            var ids = cursor == nil ? Set<String>() : Set(items.map(\.id))
            let rows = fetched.filter { !deleted.contains($0.id) && ids.insert($0.id).inserted }
            items = (cursor == nil ? rows : items + rows).sorted {
                (ISODate.parse($0.createdAt) ?? .distantPast) > (ISODate.parse($1.createdAt) ?? .distantPast)
            }
            reconcileSelection()
            nextCursor = next
            loadedPages = cursor == nil ? count : loadedPages + count
            error = nil
            pageError = nil
            didLoad = true
            hasResult = true
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
            reconcileSelection()
            await refreshCollections()
            return true
        } catch {
            if current == connectionGeneration { actionError = error.localizedDescription }
            return false
        }
    }

    func reconcileSelection() {
        if selectedItem == nil { selection = nil }
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
