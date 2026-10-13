// Keeps bounded, account-scoped session read timestamps in local preferences.
// Exports SessionReadStore, SessionReadAccount and the agent-message unread predicate.
// Dependencies: Foundation, Combine, CryptoKit and HibossKit history/session models.

import Combine
import CryptoKit
import Foundation
import HibossKit

struct SessionReadAccount: Equatable {
    let serverURL: URL
    let identity: String

    init(config: ConnectionConfig) {
        serverURL = config.serverURL
        identity = SHA256.hash(data: Data(config.bossToken.utf8)).prefix(8)
            .map { String($0, radix: 16) }.map { $0.count == 1 ? "0" + $0 : $0 }.joined()
    }

    var storageKey: String {
        let encoded = (try? JSONEncoder().encode([serverURL.absoluteString, identity])) ?? Data()
        return "hiboss.sessionRead." + encoded.base64EncodedString()
    }
}

func isUnread(sessionID: String, messages: [HistoryMessage], lastRead: Date?, baseline: Date) -> Bool {
    let cutoff = max(lastRead ?? baseline, baseline)
    return messages.contains {
        SessionGrouping.sessionKey(for: $0) == sessionID && isAgentMessage($0.direction)
            && ($0.createdDate ?? .distantPast) > cutoff
    }
}

func isAgentMessage(_ direction: String?) -> Bool {
    direction?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "agent_to_boss"
}

@MainActor
final class SessionReadStore: ObservableObject {
    private struct Record: Codable {
        var baseline: Date
        var lastRead: [String: Date] = [:]
    }

    @Published private(set) var baseline: Date = .distantFuture
    @Published private(set) var lastRead: [String: Date] = [:]
    private let defaults: UserDefaults
    private var account: SessionReadAccount?
    private static let retention: TimeInterval = 30 * 24 * 60 * 60
    private static let maximumSessions = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(_ account: SessionReadAccount?, now: Date = .now) {
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

    func markRead(_ id: String, messages: [HistoryMessage], events: [SessionEvent] = [], now: Date = .now) {
        guard account != nil else { return }
        let historyDate = messages.filter {
            SessionGrouping.sessionKey(for: $0) == id && isAgentMessage($0.direction)
        }.compactMap(\.createdDate).max() ?? now
        let eventDate = events.filter {
            $0.sessionId == id && $0.kind == "message" && isAgentMessage($0.direction)
        }.compactMap { ISOTimestamp.date(from: $0.createdAt) }.max() ?? now
        var updated = lastRead
        updated[id] = max(now, historyDate, eventDate, lastRead[id] ?? baseline)
        updated = Self.pruned(updated, now: now)
        guard updated != lastRead else { return }
        lastRead = updated
        persist()
    }

    func unreadSessionIDs(messages: [HistoryMessage]) -> Set<String> {
        let grouped = Dictionary(grouping: messages, by: SessionGrouping.sessionKey(for:))
        return Set(grouped.keys.filter {
            isUnread(sessionID: $0, messages: grouped[$0] ?? [], lastRead: lastRead[$0], baseline: baseline)
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
              let data = try? JSONEncoder().encode(Record(baseline: baseline, lastRead: lastRead)) else { return }
        defaults.set(data, forKey: account.storageKey)
    }
}
