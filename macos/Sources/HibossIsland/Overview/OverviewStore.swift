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
    private var health: TodayHealth = .loading
    private var coverageComplete = false
    private var withdrawn: Set<MessageID> = []
    private var nextExpiration: Date?
    private var expirationTask: Task<Void, Never>?
    private var requiredInputs: [HistoryMessage] = []

    deinit { expirationTask?.cancel() }

    func update(history: [HistoryMessage], live: OptionMessage?, now: Date = .now,
                health: TodayHealth = .loading, coverageComplete: Bool = false,
                withdrawn: Set<MessageID> = [], requiredInputs: [HistoryMessage] = []) {
        let expired = nextExpiration.map { $0 <= now } ?? false
        guard history != self.history || live != self.live || health != self.health
            || coverageComplete != self.coverageComplete || withdrawn != self.withdrawn || expired
            || requiredInputs != self.requiredInputs
        else { return }
        self.history = history
        self.live = live
        self.health = health
        self.coverageComplete = coverageComplete
        self.withdrawn = withdrawn
        self.requiredInputs = requiredInputs
        snapshot = OverviewSnapshot(history: history, live: live, now: now,
            health: health, coverageComplete: coverageComplete, withdrawn: withdrawn,
            requiredInputs: requiredInputs)
        scheduleExpiration(after: now)
    }

    private func scheduleExpiration(after now: Date) {
        expirationTask?.cancel()
        let activity = snapshot.today.working.compactMap(\.lastActivityDate)
            .map { $0.addingTimeInterval(TodaySession.activityWindow + 1) }
        let delivered = snapshot.today.delivered.compactMap { HistoryTimestamp.date(from: $0.createdAt) }
            .map { $0.addingTimeInterval(TodaySnapshot.deliveredWindow + 1) }
        nextExpiration = (snapshot.attention.compactMap(\.expirationDate) + activity + delivered)
            .filter { $0 > now }.min()
        guard let nextExpiration else { return }
        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, nextExpiration.timeIntervalSinceNow)))
                try Task.checkCancellation()
            } catch { return }
            guard let self else { return }
            self.update(history: self.history, live: self.live,
                health: self.health, coverageComplete: self.coverageComplete, withdrawn: self.withdrawn,
                requiredInputs: self.requiredInputs)
        }
    }
}
