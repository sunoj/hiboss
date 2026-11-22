// In-memory boss session inventory per account: one full read, then deltas since the server cursor.
// Exports SessionInventoryPage and SessionInventoryCache; a server without cursors stays full-read.
// Dependencies: Foundation, CryptoKit (account key) and ProjectSession.

import CryptoKit
import Foundation

/// One `GET /api/boss/sessions` answer; `removed` is present only on a delta.
public struct SessionInventoryPage: Decodable, Sendable {
    public let sessions: [ProjectSession]
    public let removed: [String]?
    public let cursor: String?

    public init(sessions: [ProjectSession], removed: [String]? = nil, cursor: String? = nil) {
        self.sessions = sessions
        self.removed = removed
        self.cursor = cursor
    }
}

public actor SessionInventoryCache {
    public static let shared = SessionInventoryCache()
    /// A full read now and then picks up access changes, which a delta cannot see.
    public static let fullReadInterval: TimeInterval = 6 * 60 * 60

    private struct Entry {
        var sessions: [String: ProjectSession]
        var cursor: String
        var fullReadAt: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// The cache key of an account: its server and a digest of its token, never the token itself.
    public static func key(for config: ConnectionConfig) -> String {
        let digest = SHA256.hash(data: Data(config.bossToken.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(config.serverURL.absoluteString)|\(digest.prefix(32))"
    }

    /// The account's inventory, newest heartbeat first. `fetch(nil)` reads everything; `fetch(cursor)`
    /// reads the changes since it. A failed delta falls back to one full read.
    public func sessions(
        key: String, now: Date = .now,
        fetch: @Sendable (String?) async throws -> SessionInventoryPage
    ) async throws -> [ProjectSession] {
        if let entry = entries[key], now.timeIntervalSince(entry.fullReadAt) < Self.fullReadInterval,
           let delta = try? await fetch(entry.cursor), let next = delta.cursor {
            var merged = entries[key] ?? entry
            for id in delta.removed ?? [] { merged.sessions[id] = nil }
            for session in delta.sessions { merged.sessions[session.id] = session }
            merged.cursor = max(merged.cursor, next)
            entries[key] = merged
            return Self.ordered(merged.sessions.values)
        }
        let page = try await fetch(nil)
        if let cursor = page.cursor {
            entries[key] = Entry(sessions: Dictionary(page.sessions.map { ($0.id, $0) }, uniquingKeysWith: { $1 }),
                                 cursor: cursor, fullReadAt: now)
        } else {
            entries[key] = nil
        }
        return page.sessions
    }

    public func reset() { entries.removeAll() }

    /// The server's full-list order: newest `last_seen_at` first ("yyyy-MM-dd HH:mm:ss" sorts as text).
    static func ordered(_ sessions: some Sequence<ProjectSession>) -> [ProjectSession] {
        sessions.sorted { lhs, rhs in
            let left = lhs.lastSeenAt ?? "", right = rhs.lastSeenAt ?? ""
            return left == right ? lhs.id < rhs.id : left > right
        }
    }
}
