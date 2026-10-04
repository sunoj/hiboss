// The one mapping from a session's status word to its label, glyph and tint on every iOS surface.
// Exports: SessionStatus (the five server words) and SessionStatusStyle (card style; unknown words kept).
// Dependencies: SwiftUI Color and Theme tokens. Home's "Waiting on you" group and Sessions read it.

import SwiftUI

/// Session status words the server and CLI accept (`hiboss ss`, `server/src/routes/sessions.ts`).
/// `waiting` is what a blocking ask sets: the agent has stopped until the boss answers.
enum SessionStatus: String, CaseIterable {
    case working
    case blocked
    case waiting
    case idle
    case completed

    /// Trimmed, case-insensitive parse; nil for an empty or unknown word.
    init?(word: String?) {
        guard let word = word?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        self.init(rawValue: word)
    }

    var title: LocalizedStringResource {
        switch self {
        case .working: "Working"
        case .blocked: "Blocked"
        case .waiting: "Waiting on you"
        case .idle: "Idle"
        case .completed: "Completed"
        }
    }

    var icon: String {
        switch self {
        case .working: "ellipsis.circle.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .waiting: "hand.raised.fill"
        case .idle: "pause.circle.fill"
        case .completed: "checkmark.circle.fill"
        }
    }

    /// Red only for an agent that reports itself blocked; orange for one waiting on the boss.
    var tint: Color {
        switch self {
        case .blocked: Theme.negative
        case .waiting: Theme.warn
        case .working, .idle, .completed: Theme.ink2
        }
    }
}

/// Localized status word, glyph, and tint for a session board card.
struct SessionStatusStyle {
    let label: String
    let icon: String
    let tint: Color

    init?(word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let status = SessionStatus(word: trimmed) {
            label = String(localized: status.title)
            icon = status.icon
            tint = status.tint
        } else {
            label = trimmed.capitalized
            icon = "circle.fill"
            tint = Theme.ink2
        }
    }
}
