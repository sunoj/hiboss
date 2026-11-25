// Keeps the USB status lamp in step with the overview: steady signal, arrival flash, liveness.
// Exports: LampController.
// Dependencies: Combine, OverviewStore snapshot, BossPreferences, LampSignal, LampPortWriting.

import Combine
import Foundation
import HibossKit

@MainActor
final class LampController {
    /// Under the firmware's 90 s staleness cutoff, and the clock for the expiring window.
    static let resendInterval: TimeInterval = 15
    private let port: any LampPortWriting
    private let now: () -> Date
    private var snapshot: OverviewSnapshot?
    private var preferences = BossPreferences()
    private var arrivals = LampArrivals()
    private var cancellables: Set<AnyCancellable> = []
    private var timer: Timer?

    init(port: any LampPortWriting, now: @escaping () -> Date = Date.init) {
        self.port = port
        self.now = now
    }

    func start(snapshots: AnyPublisher<OverviewSnapshot, Never>,
               preferences: AnyPublisher<BossPreferences, Never>) {
        // Use emitted values: every `@Published` emits before its property changes.
        Publishers.CombineLatest(snapshots, preferences)
            .sink { [weak self] snapshot, preferences in
                self?.receive(snapshot: snapshot, preferences: preferences)
            }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: Self.resendInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func receive(snapshot: OverviewSnapshot, preferences: BossPreferences) {
        let changed = self.snapshot == nil || currentSignal() != signal(for: snapshot, preferences)
        self.snapshot = snapshot
        self.preferences = preferences
        if changed { refresh() }
        if arrivals.hasArrival(in: snapshot.history, now: now()) { port.send(LampSignal.flashCommand) }
    }

    /// Resends the steady signal: a replugged lamp catches up and a live one never goes stale.
    func refresh() {
        port.send(currentSignal().command)
    }

    /// At quit the lamp goes dark now rather than at the firmware's staleness cutoff.
    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        port.send(LampSignal.off.command)
        port.drain()
    }

    private func currentSignal() -> LampSignal {
        snapshot.map { signal(for: $0, preferences) } ?? .off
    }

    private func signal(for snapshot: OverviewSnapshot, _ preferences: BossPreferences) -> LampSignal {
        LampSignal.signal(decisions: snapshot.today.decisions, loaded: snapshot.answerability.isLoaded,
            preferences: preferences, now: now())
    }
}
