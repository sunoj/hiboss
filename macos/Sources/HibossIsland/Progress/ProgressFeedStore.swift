// Serializes progress reads and mutations while preserving the server's timeline order.
// Exports: ProgressFeedStore with project filtering, cursor paging, likes and deletion.
// Dependencies: Combine, HibossKit ProgressServing and the macOS localization catalog.

import Combine
import Foundation
import HibossKit

@MainActor
final class ProgressFeedStore: ObservableObject {
    typealias Provider = @MainActor () -> (any ProgressServing)?
    @Published private(set) var posts: [ProgressPost] = []
    @Published private(set) var projects: [ProgressProject] = []
    @Published private(set) var selectedProject: String?
    @Published private(set) var didLoad = false
    @Published private(set) var hasResult = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var nextCursor: ProgressCursor?
    @Published private(set) var loadError: String?
    @Published private(set) var pageError: String?
    @Published private(set) var likingIDs: Set<String> = []
    @Published private(set) var deletingIDs: Set<String> = []
    @Published private(set) var actionErrors: [String: String] = [:]
    private let apiProvider: Provider
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var accountGeneration = 0
    private var deletedIDs: Set<String> = []

    init(apiProvider: @escaping Provider) { self.apiProvider = apiProvider }

    func reset() {
        generation += 1
        accountGeneration += 1
        operation?.cancel()
        operation = nil
        posts = []
        projects = []
        selectedProject = nil
        didLoad = false
        hasResult = false
        isRefreshing = false
        isLoadingMore = false
        nextCursor = nil
        loadError = nil
        pageError = nil
        likingIDs = []
        deletingIDs = []
        actionErrors = [:]
        deletedIDs = []
    }

    static func groupProjects(_ rows: [ProgressProject]) -> [ProgressProject] {
        Dictionary(grouping: rows, by: \.slug).map { slug, rows in
            ProgressProject(project: slug, count: rows.reduce(0) { $0 + $1.count },
                lastPostAt: rows.compactMap(\.lastPostAt).max(), agentId: "",
                projectRef: rows.first?.projectRef)
        }.sorted { $0.slug < $1.slug }
    }

    func selectProject(_ project: String?) async {
        guard project != selectedProject else { return }
        generation += 1
        selectedProject = project
        pageError = nil
        await refresh()
    }

    func refresh() async {
        await enqueue { store, current in await store.fetchPage(cursor: nil, generation: current) }
    }

    func loadMore() async {
        await enqueue { store, current in
            guard let cursor = store.nextCursor else { return }
            await store.fetchPage(cursor: cursor, generation: current)
        }
    }

    private func enqueue(accountScoped: Bool = false,
                         _ action: @escaping @MainActor (ProgressFeedStore, Int) async -> Void) async {
        let previous = operation
        let current = accountScoped ? accountGeneration : generation
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, current == (accountScoped ? accountGeneration : generation),
                  !Task.isCancelled else { return }
            await action(self, current)
        }
        operation = task
        await task.value
    }

    private func fetchPage(cursor: ProgressCursor?, generation current: Int) async {
        if cursor == nil { isRefreshing = true } else { isLoadingMore = true }
        defer {
            if current == generation {
                isRefreshing = false
                isLoadingMore = false
            }
        }
        do {
            guard let api = apiProvider() else { throw ProgressFeedError.notConfigured }
            let page = try await api.progressFeed(project: selectedProject, limit: 20, before: cursor)
            guard current == generation, !Task.isCancelled else { return }
            var ids = cursor == nil ? Set<String>() : Set(posts.map(\.id))
            let rows = page.posts.filter { !deletedIDs.contains($0.id) && ids.insert($0.id).inserted }
            posts = cursor == nil ? rows : posts + rows
            nextCursor = page.nextCursor
            loadError = nil
            pageError = nil
            didLoad = true
            hasResult = true
            if cursor == nil, let rows = try? await api.progressProjects(), current == generation {
                projects = Self.groupProjects(rows)
            }
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            if cursor == nil { loadError = error.localizedDescription }
            else { pageError = error.localizedDescription }
            didLoad = true
        }
    }

    func toggleLike(id: String) async {
        guard !likingIDs.contains(id), !deletingIDs.contains(id) else { return }
        let current = accountGeneration
        likingIDs.insert(id)
        actionErrors[id] = nil
        defer { if current == accountGeneration { likingIDs.remove(id) } }
        await enqueue(accountScoped: true) { store, current in
            await store.performLike(id: id, generation: current)
        }
    }

    private func performLike(id: String, generation current: Int) async {
        guard let original = posts.first(where: { $0.id == id }) else { return }
        replace(original.withLike(count: max(0, original.likeCount + (original.liked ? -1 : 1)),
            liked: !original.liked))
        do {
            guard let api = apiProvider() else { throw ProgressFeedError.notConfigured }
            let result = original.liked
                ? try await api.unlikeProgressPost(id: id) : try await api.likeProgressPost(id: id)
            guard current == accountGeneration, !Task.isCancelled else { return }
            replace(original.withLike(count: result.likeCount, liked: result.liked))
        } catch {
            guard current == accountGeneration else { return }
            replace(original)
            actionErrors[id] = L("Couldn't update this like. Try again.")
        }
    }

    func delete(id: String) async {
        guard !deletingIDs.contains(id), !likingIDs.contains(id) else { return }
        let current = accountGeneration
        deletingIDs.insert(id)
        actionErrors[id] = nil
        defer { if current == accountGeneration { deletingIDs.remove(id) } }
        await enqueue(accountScoped: true) { store, current in
            await store.performDelete(id: id, generation: current)
        }
    }

    private func performDelete(id: String, generation current: Int) async {
        do {
            guard let api = apiProvider() else { throw ProgressFeedError.notConfigured }
            try await api.deleteProgressPost(id: id)
            guard current == accountGeneration, !Task.isCancelled else { return }
            deletedIDs.insert(id)
            posts.removeAll { $0.id == id }
        } catch {
            if current == accountGeneration { actionErrors[id] = error.localizedDescription }
        }
    }

    private func replace(_ post: ProgressPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index] = post }
    }
}

enum ProgressFeedError: LocalizedError {
    case notConfigured
    var errorDescription: String? { L("Connect to HiBoss to browse progress.") }
}
