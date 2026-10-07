// Explains a slow reply without issuing a second write or losing the typed draft.
// Exports ReplyPendingNote for Home, detail and transcript decision controls.
// Dependencies: PendingStateView and the app's connection Settings action.

import SwiftUI

struct ReplyPendingNote: View {
    let onSettings: () -> Void

    var body: some View {
        PendingStateView(
            title: String(localized: "Sending reply…"),
            detail: String(localized:
                "Your reply is still sending. Check the connection before trying again."),
            onSettings: onSettings
        )
    }
}
