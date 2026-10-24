// Account-session state for thumbnail backfill PUTs, shared by every Box browser window.
// Exports BoxBackfillSession: 405 turns backfill off, 404 or a rejection settles one item,
// a transient failure allows one retry on a later load. Dependencies: HibossKit.

import HibossKit

@MainActor
final class BoxBackfillSession {
    static let shared = BoxBackfillSession()
    static let attemptsPerItem = 2

    private(set) var enabled = true
    private var settled: Set<String> = []
    private var attempts: [String: Int] = [:]

    /// Claims one PUT for `id`; false when backfill is off, the item is settled or out of attempts.
    func begin(_ id: String) -> Bool {
        guard enabled, !settled.contains(id), attempts[id, default: 0] < Self.attemptsPerItem
        else { return false }
        attempts[id, default: 0] += 1
        return true
    }

    /// An account change starts over: backfill on, nothing settled.
    func reset() { (enabled, settled, attempts) = (true, [], [:]) }

    func succeeded(_ id: String) { settled.insert(id) }

    func failed(_ id: String, error: Error) {
        guard case let HibossAPIError.requestFailed(status, _) = error else { return }
        if status == 405 {
            enabled = false
        } else if (400..<500).contains(status), status != 408, status != 429 {
            settled.insert(id)
        }
    }
}
