// Decides Island visibility from pointer, presentation and Box activity events.
// Exports IslandDropRevealPolicy with a single pending transition deadline.
// Dependencies: Foundation time intervals; no windows, clocks or timers.

import Foundation

struct IslandDropRevealPolicy {
    enum Visibility: Equatable { case hidden, dropTarget, question }
    enum Event {
        case pointer(inHotZone: Bool, dragging: Bool)
        case activity(popover: Bool, uploading: Bool)
        case presentation(island: Bool, question: Bool)
        case deadline
    }

    private(set) var visibility: Visibility = .hidden
    private(set) var nextDeadline: TimeInterval?
    private var island = false
    private var question = false
    private var inside = false
    private var held = false
    private var revealed = false
    private var enteredAt: TimeInterval?
    private var leftAt: TimeInterval?

    mutating func send(_ event: Event, at now: TimeInterval) {
        switch event {
        case let .presentation(island, question):
            if self.island != island || self.question != question {
                inside = false
                revealed = false
                enteredAt = nil
                leftAt = nil
            }
            self.island = island
            self.question = question
        case let .pointer(inHotZone, dragging):
            guard island, !question else { return }
            if inHotZone && !inside { enteredAt = now }
            if !inHotZone && inside { leftAt = now }
            inside = inHotZone
            if inside {
                leftAt = nil
                if dragging { revealed = true }
            } else {
                enteredAt = nil
            }
        case let .activity(popover, uploading):
            held = popover || uploading
        case .deadline:
            break
        }
        evaluate(at: now)
    }

    private mutating func evaluate(at now: TimeInterval) {
        nextDeadline = nil
        guard island else {
            visibility = .hidden
            return
        }
        guard !question else {
            visibility = .question
            return
        }
        if inside, let enteredAt, !revealed {
            let deadline = enteredAt + 0.3
            if now >= deadline { revealed = true } else { nextDeadline = deadline }
        }
        if revealed, !inside, !held {
            let deadline = (leftAt ?? now) + 1
            if now >= deadline { revealed = false } else { nextDeadline = deadline }
        }
        visibility = revealed ? .dropTarget : .hidden
    }
}
