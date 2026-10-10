// Stores bounded history for one active account, with hashed credential lookup for offline launch.
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
    private var activeAccount: String?
    private var marker: URL { directory.appendingPathComponent("active-account") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("HiBoss/History", isDirectory: true)
    }

    func load(for key: HistoryCacheKey) throws -> (epoch: Int, cached: (String, HistorySnapshot)?) {
        try activate(key)
        let epoch = epochs[key.server, default: 0]
        let root = directory.appendingPathComponent(key.server, isDirectory: true)
        let lookup = root.appendingPathComponent("lookup-" + key.credential)
        guard FileManager.default.fileExists(atPath: lookup.path) else { return (epoch, nil) }
        let bossID = try JSONDecoder().decode(String.self, from: Data(contentsOf: lookup))
        let file = root.appendingPathComponent(HistoryCacheKey.digest(bossID) + ".json")
        let snapshot = try JSONDecoder().decode(HistorySnapshot.self, from: Data(contentsOf: file))
        return (epoch, (bossID, snapshot))
    }

    func save(_ snapshot: HistorySnapshot, bossID: String, key: HistoryCacheKey, epoch: Int) throws {
        guard activeAccount == key.account, epoch == epochs[key.server, default: 0] else { return }
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
        let account = try activeAccount ?? readMarker()
        if account?.hasPrefix(server + ":") == true {
            activeAccount = nil
            if FileManager.default.fileExists(atPath: marker.path) {
                try FileManager.default.removeItem(at: marker)
            }
        }
        let root = directory.appendingPathComponent(server, isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    private func activate(_ key: HistoryCacheKey) throws {
        let previous = try readMarker()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protect(directory)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        if previous != key.account, previous != nil || !files.isEmpty {
            activeAccount = nil
            let servers = Set(epochs.keys).union(files.map(\.lastPathComponent)).union([key.server])
            for server in servers { epochs[server, default: 0] += 1 }
            for file in files { try FileManager.default.removeItem(at: file) }
        }
        epochs[key.server] = epochs[key.server, default: 0]
        if previous != key.account { try write(JSONEncoder().encode(key.account), to: marker) }
        activeAccount = key.account
    }

    private func readMarker() throws -> String? {
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let data = try Data(contentsOf: marker)
        return try? JSONDecoder().decode(String.self, from: data)
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
