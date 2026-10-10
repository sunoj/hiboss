// Stores bounded history per server and boss, with hashed credential lookup for offline launch.
// Exports HistoryCache and HistorySnapshot; serializes disk access and deletion epochs.
// Depends on Foundation Application Support storage; contains no tokens.

import Foundation

public struct HistorySnapshot: Codable, Equatable, Sendable {
    public var messages: [HistoryMessage]
    public var cursor: String?
    public var fullFetchedAt: Date?

    public init(messages: [HistoryMessage] = [], cursor: String? = nil, fullFetchedAt: Date? = nil) {
        self.messages = messages
        self.cursor = cursor
        self.fullFetchedAt = fullFetchedAt
    }
}

public actor HistoryCache {
    public static let shared = HistoryCache()
    private let directory: URL
    private var epochs: [String: Int] = [:]

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("HiBoss/History", isDirectory: true)
    }

    func epoch(for key: HistoryCacheKey) -> Int { epochs[key.server, default: 0] }

    func load(for key: HistoryCacheKey) throws -> (String, HistorySnapshot)? {
        let root = directory.appendingPathComponent(key.server, isDirectory: true)
        let lookup = root.appendingPathComponent("lookup-" + key.credential)
        guard FileManager.default.fileExists(atPath: lookup.path) else { return nil }
        let bossID = try JSONDecoder().decode(String.self, from: Data(contentsOf: lookup))
        let file = root.appendingPathComponent(HistoryCacheKey.digest(bossID) + ".json")
        let snapshot = try JSONDecoder().decode(HistorySnapshot.self, from: Data(contentsOf: file))
        return (bossID, snapshot)
    }

    func save(_ snapshot: HistorySnapshot, bossID: String, key: HistoryCacheKey, epoch: Int) throws {
        guard epoch == epochs[key.server, default: 0] else { return }
        let root = directory.appendingPathComponent(key.server, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try protect(root)
        let file = root.appendingPathComponent(HistoryCacheKey.digest(bossID) + ".json")
        try write(JSONEncoder().encode(snapshot), to: file)
        try write(JSONEncoder().encode(bossID), to: root.appendingPathComponent("lookup-" + key.credential))
    }

    /// Removes all identities for the signed-out server and rejects outstanding writes.
    public func delete(serverURL: URL) throws {
        let server = HistoryCacheKey.digest(serverURL.absoluteString)
        epochs[server, default: 0] += 1
        let root = directory.appendingPathComponent(server, isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    private func write(_ data: Data, to file: URL) throws {
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try protect(file)
    }

    private func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path
        )
        #endif
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
