// The one session-unread rule and its bounded, account-scoped read timestamps.
// Exports: SessionUnread (agent_to_boss only), SessionReadAccount, and SessionReadStore.
// Dependencies: Foundation, Combine, CryptoKit, SessionGrouping, SessionEvent, and ISODate.

import Combine
import CryptoKit
import Foundation

/// Only an agent→boss message makes a session unread (docs/session-unread-and-timestamps.md).
/// Boss→agent and agent→agent rows never light the dot.
public enum SessionUnread {
    public static func counts(direction: String?) -> Bool {
        direction?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "agent_to_boss"
    }

    public static func isUnread(sessionID: String, messages: [HistoryMessage],
                                lastRead: Date?, baseline: Date) -> Bool {
        let cutoff = max(lastRead ?? baseline, baseline)
        return messages.contains {
            SessionGrouping.sessionKey(for: $0) == sessionID && counts(direction: $0.direction)
                && (ISODate.parse($0.createdAt) ?? .distantPast) > cutoff
        }
    }
}

public struct SessionReadAccount: Equatable, Sendable {
    public let serverURL: URL
    public let identity: String

    public init(serverURL: URL, identity: String) {
        self.serverURL = serverURL
        self.identity = identity
    }

    /// Scoped by server and the first 16 hex characters of the token's SHA-256; never the token.
    public init(config: ConnectionConfig) {
        let digest = SHA256.hash(data: Data(config.bossToken.utf8))
        self.init(serverURL: config.serverURL,
                  identity: digest.prefix(8).map { String(format: "%02x", $0) }.joined())
    }

    public var storageKey: String {
        let encoded = (try? JSONEncoder().encode([serverURL.absoluteString, identity])) ?? Data()
        return "hiboss.sessionRead." + encoded.base64EncodedString()
    }
}

@MainActor
public final class SessionReadStore: ObservableObject {
    private struct Record: Codable {
        var baseline: Date
        var lastRead: [String: Date] = [:]
    }

    @Published public private(set) var baseline: Date = .distantFuture
    @Published public private(set) var lastRead: [String: Date] = [:]
    private let defaults: UserDefaults
    private var account: SessionReadAccount?
    private static let retention: TimeInterval = 30 * 24 * 60 * 60
    private static let maximumSessions = 500

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func activate(_ account: SessionReadAccount?, now: Date = .now) {
        guard account != self.account else { return }
        self.account = account
        guard let account else {
            baseline = .distantFuture
            lastRead = [:]
            return
        }
        let stored = defaults.data(forKey: account.storageKey)
            .flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
        baseline = stored?.baseline ?? now
        lastRead = Self.pruned(stored?.lastRead ?? [:], now: now)
        persist()
    }

    public func markRead(_ id: String, messages: [HistoryMessage], events: [SessionEvent] = [],
                         now: Date = .now) {
        guard account != nil else { return }
        let historyDate = messages.filter {
            SessionGrouping.sessionKey(for: $0) == id && SessionUnread.counts(direction: $0.direction)
        }.compactMap { ISODate.parse($0.createdAt) }.max() ?? now
        let eventDate = events.filter {
            $0.sessionId == id && $0.kind == "message" && SessionUnread.counts(direction: $0.direction)
        }.compactMap { ISODate.parse($0.createdAt) }.max() ?? now
        var updated = lastRead
        updated[id] = max(now, historyDate, eventDate, lastRead[id] ?? baseline)
        updated = Self.pruned(updated, now: now)
        guard updated != lastRead else { return }
        lastRead = updated
        persist()
    }

    public func unreadSessionIDs(messages: [HistoryMessage]) -> Set<String> {
        let grouped = Dictionary(grouping: messages, by: SessionGrouping.sessionKey(for:))
        return Set(grouped.keys.filter {
            SessionUnread.isUnread(sessionID: $0, messages: grouped[$0] ?? [],
                                   lastRead: lastRead[$0], baseline: baseline)
        })
    }

    private static func pruned(_ entries: [String: Date], now: Date) -> [String: Date] {
        let retained = entries.filter { $0.value >= now.addingTimeInterval(-retention) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(maximumSessions)
        return Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let account,
              let data = try? JSONEncoder().encode(Record(baseline: baseline, lastRead: lastRead)) else {
            return
        }
        defaults.set(data, forKey: account.storageKey)
    }
}
