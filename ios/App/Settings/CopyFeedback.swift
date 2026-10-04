// Transient "Copied" state for a copy button: each copy shows it and restarts its window.
// Exports: CopyFeedback. A view drives the haptic from `count` and hides the state with `expire`.
// Dependencies: Foundation.

import Foundation

struct CopyFeedback: Equatable {
    /// How long the confirmation stays on the button after the latest copy.
    static let duration: Duration = .seconds(2)

    /// Increments on every copy; a sensory-feedback and expiry trigger.
    private(set) var count = 0
    private(set) var isShowing = false

    mutating func copied() {
        count += 1
        isShowing = true
    }

    /// Hides the confirmation only when no later copy has restarted it.
    mutating func expire(copy: Int) {
        if copy == count { isShowing = false }
    }
}
