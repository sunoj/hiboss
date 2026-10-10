// Connection freshness supplied by the caller without networking or a clock read.
// Exports: TodayHealth for TodaySnapshot's live and unavailable states.
// Dependencies: Foundation Date.

import Foundation

public enum TodayHealth: Equatable, Sendable {
    case live(checkedAt: Date)
    case connecting
    case offline(since: Date)
    case loading
}
