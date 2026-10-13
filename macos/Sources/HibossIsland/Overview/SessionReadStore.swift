// Keeps bounded, account-scoped session read timestamps in local preferences.
// Exports: SessionReadStore, SessionReadAccount, and the pure isUnread predicate.
// Dependencies: Foundation, Combine, CryptoKit, and HibossKit session/message models.

import Combine
import CryptoKit
import Foundation
import HibossKit

struct SessionReadAccount: Equatable {
    let serverURL: URL
    let identity: String

    var storageKey: String {
        let components = [serverURL.absoluteString, identity]
        let encoded = (try? JSONEncoder().encode(components)) ?? Data()
        return "hiboss.sessionRead." + encoded.base64EncodedString()
    }
}

extension SessionReadAccount {
    init(config: ConnectionConfig) {
        let digest = SHA256.hash(data: Data(config.bossToken.utf8))
        let fingerprint = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        self.init(serverURL: config.serverURL, identity: fingerprint)
    }
}

func isUnread(session: TodaySession, messages: [HistoryMessage],
              lastRead: Date?, baseline: Date) -> Bool {
    let cutoff = max(lastRead ?? baseline, baseline)
    return messages.contains { message in
        let direction = message.direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard direction != "boss_to_agent",
              SessionGrouping.sessionKey(for: message) == session.id,
              let created = HistoryTimestamp.date(from: message.createdAt) else { return false }
        return created > cutoff
    }
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

    func markRead(_ id: String, messages: [HistoryMessage], now: Date = .now) {
        guard account != nil else { return }
        let latest = messages.filter {
            SessionGrouping.sessionKey(for: $0) == id
                && $0.direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    != "boss_to_agent"
        }.compactMap { HistoryTimestamp.date(from: $0.createdAt) }.max() ?? now
        let timestamp = max(now, latest, lastRead[id] ?? baseline)
        var updated = lastRead
        updated[id] = timestamp
        updated = Self.pruned(updated, now: now)
        guard updated != lastRead else { return }
        lastRead = updated
        persist()
    }

    func unreadSessionIDs(in snapshot: OverviewSnapshot) -> Set<String> {
        let directory = snapshot.today.sessionDirectory
        let messages = Dictionary(grouping: snapshot.history, by: SessionGrouping.sessionKey(for:))
        return Set((directory.needsYou + directory.working + directory.idle).filter {
            isUnread(session: $0, messages: messages[$0.id] ?? [],
                lastRead: lastRead[$0.id], baseline: baseline)
        }.map(\.id))
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
