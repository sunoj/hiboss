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
    private var closedDecisionIDs: Set<MessageID> = []
    private var requiredListingVersion = 0
    private var lastSeen: [String: Date] = [:]

    deinit { expirationTask?.cancel() }

    func answer(_ text: String, for id: MessageID, message: HistoryMessage? = nil,
                using send: (String, MessageID) async -> ReplyFeedback?) async -> ReplyFeedback? {
        guard let target = snapshot.history.first(where: { $0.id == id }) ?? message,
              snapshot.answerability.permitsReply(to: target) else { return .alreadyResolved }
        let feedback = await send(text, id)
        guard feedback == nil || feedback == .alreadyResolved else { return feedback }
        var closed = closedDecisionIDs
        closed.insert(id)
        var settled = history
        if feedback == nil {
            settled.removeAll { $0.id == id || $0.id.rawValue == "local-reply:\(id.rawValue)" }
            settled.append(answered(target))
            settled.append(HistoryMessage(id: MessageID(rawValue: "local-reply:\(id.rawValue)"),
                body: text.trimmingCharacters(in: .whitespacesAndNewlines), direction: "boss_to_agent",
                status: "sent", priority: "normal", replyTo: id.rawValue,
                metadata: MessageMetadata(options: [], source: "macos"),
                createdAt: ISO8601DateFormatter().string(from: .now), targetSessionId: target.sessionId))
        }
        update(history: settled, live: live, health: health, coverageComplete: coverageComplete,
            requiredInputs: requiredInputs, requiredInputLoaded: requiredInputLoaded,
            closedDecisionIDs: closed)
        return feedback
    }

    func bind(flow: OptionFlowStore, inputs: RequiredInputStore) {
        bind(flow: flow, requiredInputs: inputs.$state.eraseToAnyPublisher())
    }

    func bind(flow: OptionFlowStore, requiredInputs: AnyPublisher<RequiredInputState, Never>) {
        cancellables.removeAll()
        closedDecisionIDs = []
        requiredListingVersion = 0
        flow.$projectSessions
            .sink { [weak self] sessions in self?.setHeartbeats(sessions) }
            .store(in: &cancellables)
        Publishers.CombineLatest3(
            Publishers.CombineLatest3(flow.$historyMessages, flow.$activeMessage, flow.$replyFeedback),
            Publishers.CombineLatest3(flow.$connectionState, flow.$historyState, flow.$historyLoadedAt),
            requiredInputs
        )
        .sink { [weak self] messages, connection, inputs in
            let now = Date.now
            let health = TodayProjection.health(connection: connection.0,
                history: connection.1, checkedAt: now, loadedAt: connection.2)
            self?.requiredCoverageComplete = inputs.coverageComplete
            guard let self else { return }
            var closed = self.closedDecisionIDs
            if inputs.listingVersion != self.requiredListingVersion {
                if inputs.listingVersion == 0 { closed = [] }
                else { closed.subtract(inputs.listedIDs) }
                self.requiredListingVersion = inputs.listingVersion
            }
            closed.formUnion(messages.2.compactMap { $0.value == .alreadyResolved ? $0.key : nil })
            self.update(history: self.retainAccepted(in: messages.0, closed: closed),
                live: messages.1, now: now,
                health: health, coverageComplete: inputs.coverageComplete
                    && self.questionnaireCoverageComplete,
                requiredInputs: inputs.messages, requiredInputLoaded: inputs.loaded && !inputs.failed,
                closedDecisionIDs: closed)
        }
        .store(in: &cancellables)
    }

    private func retainAccepted(in incoming: [HistoryMessage], closed: Set<MessageID>) -> [HistoryMessage] {
        let local = history.filter { $0.direction == "boss_to_agent"
            && $0.replyTo.map { closed.contains(MessageID(rawValue: $0)) } == true }
        let parents = Set(local.compactMap(\.replyTo))
        var result = incoming
        for parent in history where parents.contains(parent.id.rawValue) {
            result.removeAll { $0.id == parent.id }
            result.append(parent)
        }
        for reply in local where !incoming.contains(where: { $0.replyTo == reply.replyTo }) {
            result.append(reply)
        }
        return result
    }

    private func answered(_ message: HistoryMessage) -> HistoryMessage {
        HistoryMessage(id: message.id, body: message.body, agentName: message.agentName,
            direction: message.direction, status: "replied", priority: message.priority,
            channel: message.channel, mode: message.mode, type: message.type, replyTo: message.replyTo,
            metadata: message.metadata, expiresAt: message.expiresAt, createdAt: message.createdAt,
            updatedAt: message.updatedAt, sessionId: message.sessionId,
            targetSessionId: message.targetSessionId, sessionLabel: message.sessionLabel,
            sessionBranch: message.sessionBranch, sessionStatus: message.sessionStatus)
    }

    /// Session heartbeats decide whether a "working" status is still working now.
    func setHeartbeats(_ sessions: [ProjectSession]) {
        let map = ProjectSession.heartbeats(sessions)
        guard map != lastSeen else { return }
        lastSeen = map
        snapshot = OverviewSnapshot(history: history, live: live, now: .now,
            health: health, coverageComplete: coverageComplete,
            requiredInputs: requiredInputs, requiredInputLoaded: requiredInputLoaded,
            closedDecisionIDs: closedDecisionIDs, lastSeen: lastSeen)
    }

    func setQuestionnaireCoverage(_ complete: Bool) {
        questionnaireCoverageComplete = complete
        update(history: history, live: live, health: health,
            coverageComplete: requiredCoverageComplete && complete, requiredInputs: requiredInputs,
            requiredInputLoaded: requiredInputLoaded, closedDecisionIDs: closedDecisionIDs)
    }

    func update(history: [HistoryMessage], live: OptionMessage?, now: Date = .now,
                health: TodayHealth = .loading, coverageComplete: Bool = false,
                requiredInputs: [HistoryMessage] = [], requiredInputLoaded: Bool = false,
                closedDecisionIDs: Set<MessageID> = []) {
        let expired = nextExpiration.map { $0 <= now } ?? false
        guard history != self.history || live != self.live || health != self.health
            || coverageComplete != self.coverageComplete || expired
            || requiredInputs != self.requiredInputs
            || requiredInputLoaded != self.requiredInputLoaded
            || closedDecisionIDs != self.closedDecisionIDs
        else { return }
        self.history = history
        self.live = live
        self.health = health
        self.coverageComplete = coverageComplete
        self.requiredInputs = requiredInputs
        self.requiredInputLoaded = requiredInputLoaded
        self.closedDecisionIDs = closedDecisionIDs
        snapshot = OverviewSnapshot(history: history, live: live, now: now,
            health: health, coverageComplete: coverageComplete,
            requiredInputs: requiredInputs, requiredInputLoaded: requiredInputLoaded,
            closedDecisionIDs: closedDecisionIDs, lastSeen: lastSeen)
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
                requiredInputs: self.requiredInputs, requiredInputLoaded: self.requiredInputLoaded,
                closedDecisionIDs: self.closedDecisionIDs)
        }
    }
}
