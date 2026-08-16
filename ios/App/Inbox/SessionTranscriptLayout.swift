// Groups session events into SMS-style bubbles, time separators, and system lines.
// Exports: SessionTranscriptLayout, SessionTranscriptItem, SessionBubbleStyle.
// Dependencies: Foundation, HibossKit SessionEvent. Presentation-only; stream model unchanged.

import Foundation
import HibossKit

struct SessionBubbleStyle: Equatable {
    var isOutgoing: Bool
    var isFirstInGroup: Bool
    var isLastInGroup: Bool
    var showsSender: Bool
}

enum SessionTranscriptItem: Identifiable, Equatable {
    case time(id: String, date: Date)
    case bubble(SessionEvent, SessionBubbleStyle)
    case system(SessionEvent)

    var id: String {
        switch self {
        case let .time(id, _): return id
        case let .bubble(event, _): return event.id
        case let .system(event): return event.id
        }
    }
}

enum SessionTranscriptLayout {
    static let distantGap: TimeInterval = 60 * 60
    static let collapseLimit = 160

    static func items(from events: [SessionEvent]) -> [SessionTranscriptItem] {
        var result: [SessionTranscriptItem] = []
        var previous: SessionEvent?
        var groupBroken = true
        for event in events {
            var broke = groupBroken
            if let previous, shouldInsertTime(from: previous, to: event) {
                if let date = parseDate(event.createdAt) {
                    result.append(.time(id: "time-\(event.id)", date: date))
                }
                broke = true
            }
            appendEvent(event, previous: previous, groupBroken: broke, into: &result)
            previous = event
            groupBroken = !isBubble(event)
        }
        return result
    }

    static func isBubble(_ event: SessionEvent) -> Bool { event.kind == "message" }

    static func isOutgoing(_ event: SessionEvent) -> Bool {
        event.direction == "boss_to_agent"
    }

    static func parseDate(_ value: String) -> Date? {
        (try? Date(value, strategy: .iso8601))
            ?? (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    static func collapsed(_ text: String, limit: Int = collapseLimit) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    static func systemLabel(for event: SessionEvent) -> String {
        let body = event.displayBody
        if body.isEmpty || body == event.kind { return event.kind }
        return "\(event.kind) · \(body)"
    }

    static func actorLabel(for event: SessionEvent) -> String {
        if let name = event.actorName, !name.isEmpty { return name }
        switch event.direction {
        case "boss_to_agent": return String(localized: "Boss")
        case "agent_to_agent": return String(localized: "Peer")
        case "agent_to_boss": return String(localized: "Agent")
        default: return String(localized: "Event")
        }
    }

    static func directionLabel(for event: SessionEvent) -> String {
        switch event.direction {
        case "boss_to_agent": return String(localized: "Boss to agent")
        case "agent_to_agent": return String(localized: "Agent to agent")
        case "agent_to_boss": return String(localized: "Agent to boss")
        default: return String(localized: "Unknown direction")
        }
    }
}

extension SessionTranscriptLayout {
    static func senderKey(for event: SessionEvent) -> String {
        let actor = event.actorAgentId ?? event.actorName ?? ""
        return "\(event.direction ?? "")|\(actor)"
    }

    private static func shouldInsertTime(from previous: SessionEvent, to event: SessionEvent) -> Bool {
        guard let start = parseDate(previous.createdAt), let end = parseDate(event.createdAt) else {
            return false
        }
        return end.timeIntervalSince(start) >= distantGap
    }

    private static func appendEvent(
        _ event: SessionEvent,
        previous: SessionEvent?,
        groupBroken: Bool,
        into result: inout [SessionTranscriptItem]
    ) {
        guard isBubble(event) else {
            result.append(.system(event))
            return
        }
        let outgoing = isOutgoing(event)
        let sameSender = previous.map { isBubble($0) && senderKey(for: $0) == senderKey(for: event) } == true
        if !groupBroken && sameSender {
            markLastBubbleNotTailed(&result)
            result.append(.bubble(event, SessionBubbleStyle(
                isOutgoing: outgoing, isFirstInGroup: false, isLastInGroup: true, showsSender: false
            )))
        } else {
            result.append(.bubble(event, SessionBubbleStyle(
                isOutgoing: outgoing, isFirstInGroup: true, isLastInGroup: true, showsSender: !outgoing
            )))
        }
    }

    private static func markLastBubbleNotTailed(_ result: inout [SessionTranscriptItem]) {
        guard let index = result.indices.last,
              case .bubble(let event, var style) = result[index] else { return }
        style.isLastInGroup = false
        result[index] = .bubble(event, style)
    }
}
