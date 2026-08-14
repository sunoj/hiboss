// Progress-feed HTTP methods on HibossAPI (feed, projects, delete, like).
// Exports: HibossAPI ProgressServing conformance.
// Dependencies: ProgressFeed models and the shared HibossAPI request helpers.

import Foundation

extension HibossAPI: ProgressServing {
    public func progressFeed(
        project: String? = nil,
        limit: Int = 20,
        before: ProgressCursor? = nil
    ) async throws -> ProgressFeedPage {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let project, !project.isEmpty { items.append(URLQueryItem(name: "project", value: project)) }
        if let before {
            let data = try JSONEncoder().encode(before)
            let cursor = String(decoding: data, as: UTF8.self)
            items.append(URLQueryItem(name: "before", value: cursor))
        }
        return try await decode(
            ProgressFeedPage.self,
            from: progressURL.appending(queryItems: items),
            context: "progress feed"
        )
    }

    public func progressProjects() async throws -> [ProgressProject] {
        try await decode(
            ProgressProjectsResponse.self,
            from: progressURL.appendingPathComponent("projects"),
            context: "progress projects"
        ).projects
    }

    public func deleteProgressPost(id: String) async throws {
        try await send("DELETE", url: progressURL.appendingPathComponent(id))
    }

    public func likeProgressPost(id: String) async throws -> ProgressLikeState {
        try await decode(
            ProgressLikeState.self,
            from: progressURL.appendingPathComponent(id).appendingPathComponent("like"),
            method: "POST",
            context: "progress like"
        )
    }

    public func unlikeProgressPost(id: String) async throws -> ProgressLikeState {
        try await decode(
            ProgressLikeState.self,
            from: progressURL.appendingPathComponent(id).appendingPathComponent("like"),
            method: "DELETE",
            context: "progress like"
        )
    }
}
