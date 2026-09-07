// Caches overview derivation until messages change or an attention deadline passes.
// Exports: OverviewStore with a single cancellable deadline refresh.
// Dependencies: Foundation, Combine, HibossKit, OverviewSnapshot.

import Foundation
import Combine
import HibossKit

@MainActor
final class OverviewStore: ObservableObject {
    @Published private(set) var snapshot = OverviewSnapshot(history: [], live: nil, now: .now)
    private var history: [HistoryMessage] = []
    private var live: OptionMessage?
    private var nextExpiration: Date?
    private var expirationTask: Task<Void, Never>?

    deinit { expirationTask?.cancel() }

    func update(history: [HistoryMessage], live: OptionMessage?, now: Date = .now) {
        let expired = nextExpiration.map { $0 <= now } ?? false
        guard history != self.history || live != self.live || expired else { return }
        self.history = history
        self.live = live
        snapshot = OverviewSnapshot(history: history, live: live, now: now)
        scheduleExpiration(after: now)
    }

    private func scheduleExpiration(after now: Date) {
        expirationTask?.cancel()
        nextExpiration = snapshot.attention.compactMap(\.expirationDate).filter { $0 > now }.min()
        guard let nextExpiration else { return }
        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, nextExpiration.timeIntervalSinceNow)))
                try Task.checkCancellation()
            } catch { return }
            guard let self else { return }
            self.update(history: self.history, live: self.live)
        }
    }
}
