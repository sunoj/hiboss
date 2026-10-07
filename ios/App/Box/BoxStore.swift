// Activity Box state with superseding reads, opaque pagination and explicit deletion.
// Exports BoxStore; keeps earlier rows on failures and never retries writes automatically.
// Dependencies: Combine and HibossKit BoxServing.

import Combine
import HibossKit

@MainActor
final class BoxStore: ObservableObject {
    @Published private(set) var items: [BoxItem] = []
    @Published private(set) var didLoad = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var pageError: String?
    @Published private(set) var deleting: Set<String> = []
    @Published var deleteError: String?
    @Published private(set) var nextCursor: String?

    let api: (any BoxServing)?
    private var read: Task<Void, Never>?
    private var generation = 0
    private var deleted: Set<String> = []

    init(api: (any BoxServing)?) {
        self.api = api
    }

    static func connectionIdentity(_ config: ConnectionConfig?) -> [String] {
        guard let config else { return [] }
        return [config.serverURL.absoluteString, config.bossToken]
    }

    func refresh() async {
        read?.cancel()
        generation += 1
        let current = generation
        isRefreshing = true
        isLoadingMore = false
        let task = Task { await fetch(cursor: nil, generation: current) }
        read = task
        await task.value
        if current == generation { isRefreshing = false }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isRefreshing, !isLoadingMore else { return }
        isLoadingMore = true
        let current = generation
        let task = Task { await fetch(cursor: cursor, generation: current) }
        read = task
        await task.value
        if current == generation { isLoadingMore = false }
    }

    func retryPage() async {
        read?.cancel()
        generation += 1
        isLoadingMore = false
        await loadMore()
    }

    private func fetch(cursor: String?, generation current: Int) async {
        guard let api else {
            error = String(localized: "Can't reach the server")
            didLoad = true
            return
        }
        do {
            let page = try await api.boxItems(filters: BoxFilters(), limit: 20, cursor: cursor)
            guard current == generation, !Task.isCancelled else { return }
            let existing = cursor == nil ? Set<String>() : Set(items.map(\.id))
            let rows = page.items.filter { !deleted.contains($0.id) && !existing.contains($0.id) }
            items = cursor == nil ? rows : items + rows
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

    func delete(_ item: BoxItem) async {
        guard let api, !deleting.contains(item.id) else { return }
        deleting.insert(item.id)
        defer { deleting.remove(item.id) }
        do {
            try await api.deleteBoxItem(id: item.id, purge: false)
            deleted.insert(item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}
