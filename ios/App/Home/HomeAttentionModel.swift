// Questionnaire projection beside the shared Today decisions.
// Exports: HomeAttentionSnapshot; decision ranking belongs to HibossKit.
// Dependencies: Foundation and HibossKit HistoryMessage.

import Foundation
import HibossKit

// A single projection drives Home rows, count, and the all-clear decision.
struct HomeAttentionSnapshot {
    let groups: [AttentionGroupItems]
    let questionnaires: [PendingQuestionnaire]

    var count: Int { groups.reduce(questionnaires.count) { $0 + $1.items.count } }

    init(
        messages: [HistoryMessage], withdrawn: Set<MessageID> = [],
        questionnaires: [PendingQuestionnaire], decisions: [AttentionItem]? = nil, terminalPanelIDs: Set<String> = [],
        now: Date = Date(), panelNow: ((String) -> Date)? = nil
    ) {
        let ranked = decisions ?? AttentionModel.items(
            from: messages.filter { !withdrawn.contains($0.id) }, now: now
        )
        groups = AttentionGroup.allCases.compactMap { group in
            let items = ranked.filter { $0.group == group }
            return items.isEmpty ? nil : AttentionGroupItems(group: group, items: items)
        }
        var seen: Set<String> = []
        let latestRevisions = questionnaires.reduce(into: [String: Int]()) { revisions, request in
            revisions[request.requestId] = max(revisions[request.requestId] ?? request.requestRevision, request.requestRevision)
        }
        self.questionnaires = questionnaires.sorted {
            if $0.requestRevision != $1.requestRevision { return $0.requestRevision > $1.requestRevision }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            if $0.requestId != $1.requestId { return $0.requestId < $1.requestId }
            return $0.panelId < $1.panelId
        }.filter { request in
            let reference = panelNow?(request.panelId) ?? now
            guard request.blocking,
                  request.requestRevision == latestRevisions[request.requestId],
                  !terminalPanelIDs.contains(request.panelId),
                  request.expiresAt.flatMap(ISOTimestamp.date(from:)).map({ $0 > reference }) ?? true else {
                return false
            }
            return seen.insert(request.requestId).inserted
        }
    }
}
