// Message priority as a typed value with display metadata.
// Exports: MessagePriority with color, label, and ordering.
// Dependencies: SwiftUI Color and the Palette tokens.

import SwiftUI

enum MessagePriority: String, CaseIterable, Sendable {
    case critical
    case high
    case normal
    case low

    init(raw: String) {
        self = MessagePriority(rawValue: raw.lowercased()) ?? .normal
    }

    /// Higher sorts first in the inbox.
    var rank: Int {
        switch self {
        case .critical: 3
        case .high: 2
        case .normal: 1
        case .low: 0
        }
    }

    var color: Color {
        switch self {
        case .critical: PriorityColor.critical
        case .high: PriorityColor.high
        case .normal: PriorityColor.normal
        case .low: PriorityColor.low
        }
    }

    /// Text tint for badges (lifted for the strongest priorities).
    var textColor: Color {
        switch self {
        case .critical: PriorityColor.criticalText
        case .high: PriorityColor.highText
        case .normal: Theme.ink3
        case .low: Theme.ink3
        }
    }

    var badge: String { rawValue.uppercased() }

    var isUrgent: Bool { self == .critical || self == .high }
}
