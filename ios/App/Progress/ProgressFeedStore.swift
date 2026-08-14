// Progress feed view model: pull-to-refresh, project filter, cursor pagination.
// Exports: ProgressFeedStore driving the 进展 tab.
// Dependencies: Combine, HibossKit ProgressServing.

import Combine
import Foundation
import HibossKit

@MainActor
final class ProgressFeedStore: ObservableObject {
    @Published private(set) var posts: [ProgressPost] = []
    @Published private(set) var projects: [ProgressProject] = []
    @Published private(set) var selectedProject: String?
    @Published private(set) var loadError: String?
    @Published private(set) var didLoad = false
    @Published private(set) var isLoadingMore = false

    private var api: (any ProgressServing)?
    private var nextCursor: ProgressCursor?
    private var operation: Task<Void, Never>?
    private static let pageSize = 20

    func start(api: any ProgressServing) {
        self.api = api
    }

    func stop() {
        api = nil
        posts = []
        projects = []
        selectedProject = nil
        operation?.cancel()
        operation = nil
        nextCursor = nil
        didLoad = false
        loadError = nil
        isLoadingMore = false
    }

    func selectProject(_ project: String?) {
        selectedProject = project
        Task { await refresh() }
    }

    func refresh() async {
        guard api != nil else { return }
        let previous = operation
        let current = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.performRefresh()
        }
        operation = current
        await current.value
    }

    private func performRefresh() async {
        guard let api else { return }
        do {
            let feed = try await api.progressFeed(
                project: selectedProject, limit: Self.pageSize, before: nil
            )
            guard !Task.isCancelled else { return }
            posts = feed.posts
            nextCursor = feed.nextCursor
            loadError = nil
            didLoad = true
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            didLoad = true
            return
        }
        if let list = try? await api.progressProjects() {
            guard !Task.isCancelled else { return }
            projects = list
        }
    }

    func loadMore() async {
        guard api != nil else { return }
        let previous = operation
        let current = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.performLoadMore()
        }
        operation = current
        await current.value
    }

    private func performLoadMore() async {
        guard let api, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let feed = try await api.progressFeed(
                project: selectedProject, limit: Self.pageSize, before: cursor
            )
            guard !Task.isCancelled else { return }
            let existing = Set(posts.map(\.id))
            posts.append(contentsOf: feed.posts.filter { !existing.contains($0.id) })
            nextCursor = feed.nextCursor
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }
}
