// Caches overview derivation until messages change or an attention deadline passes.
// Exports: OverviewStore with a single cancellable deadline refresh.
// Dependencies: Foundation, Combine, HibossKit, OverviewSnapshot.

import Foundation
import Combine
import HibossKit

@MainActor
final class OverviewStore: ObservableObject {
    @Published private(set) var snapshot = OverviewSnapshot(history: [], live: nil, now: .now)
    private var cancellables: Set<AnyCancellable> = []
    private var history: [HistoryMessage] = []
    private var live: OptionMessage?
    private var health: TodayHealth = .loading
    private var coverageComplete = false
    private var nextExpiration: Date?
    private var expirationTask: Task<Void, Never>?
    private var requiredCoverageComplete = false
    private var questionnaireCoverageComplete = true
    private var requiredInputs: [HistoryMessage] = []
    private var requiredInputLoaded = false

    deinit { expirationTask?.cancel() }

    func answer(_ text: String, for id: MessageID, message: HistoryMessage? = nil,
                using send: (String, MessageID) async -> ReplyFeedback?) async -> ReplyFeedback? {
        guard let target = snapshot.history.first(where: { $0.id == id }) ?? message,
              snapshot.answerability.permitsReply(to: target) else { return .alreadyResolved }
        return await send(text, id)
    }

    func bind(flow: OptionFlowStore, inputs: RequiredInputStore) {
        bind(flow: flow, requiredInputs: inputs.$state.eraseToAnyPublisher())
    }

    func bind(flow: OptionFlowStore, requiredInputs: AnyPublisher<RequiredInputState, Never>) {
        cancellables.removeAll()
        Publishers.CombineLatest3(
            Publishers.CombineLatest(flow.$historyMessages, flow.$activeMessage),
            Publishers.CombineLatest(flow.$connectionState, flow.$historyState),
            requiredInputs
        )
        .sink { [weak self] messages, connection, inputs in
            let now = Date.now
            let health = TodayProjection.health(connection: connection.0,
                history: connection.1, checkedAt: now)
            self?.requiredCoverageComplete = inputs.coverageComplete
            self?.update(history: messages.0, live: messages.1, now: now,
                health: health, coverageComplete: inputs.coverageComplete
                    && (self?.questionnaireCoverageComplete ?? false),
                requiredInputs: inputs.messages, requiredInputLoaded: inputs.loaded)
        }
        .store(in: &cancellables)
    }

    func setQuestionnaireCoverage(_ complete: Bool) {
        questionnaireCoverageComplete = complete
        update(history: history, live: live, health: health,
            coverageComplete: requiredCoverageComplete && complete, requiredInputs: requiredInputs,
            requiredInputLoaded: requiredInputLoaded)
    }

    func update(history: [HistoryMessage], live: OptionMessage?, now: Date = .now,
                health: TodayHealth = .loading, coverageComplete: Bool = false,
                requiredInputs: [HistoryMessage] = [], requiredInputLoaded: Bool = false) {
        let expired = nextExpiration.map { $0 <= now } ?? false
        guard history != self.history || live != self.live || health != self.health
            || coverageComplete != self.coverageComplete || expired
            || requiredInputs != self.requiredInputs
            || requiredInputLoaded != self.requiredInputLoaded
        else { return }
        self.history = history
        self.live = live
        self.health = health
        self.coverageComplete = coverageComplete
        self.requiredInputs = requiredInputs
        self.requiredInputLoaded = requiredInputLoaded
        snapshot = OverviewSnapshot(history: history, live: live, now: now,
            health: health, coverageComplete: coverageComplete,
            requiredInputs: requiredInputs, requiredInputLoaded: requiredInputLoaded)
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
                health: self.health, coverageComplete: self.coverageComplete,
                requiredInputs: self.requiredInputs, requiredInputLoaded: self.requiredInputLoaded)
        }
    }
}
