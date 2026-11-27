// Sends a form ask's structured answer from any card without threading it through every view.
// Exports: AskFormAnswerAction and EnvironmentValues.askFormAnswer, set once by MainView.
// Dependencies: SwiftUI, HibossKit PanelValue/MessageID, and AttentionReplyState.

import HibossKit
import SwiftUI

/// `(answers, summary, id)`; nil means the server accepted the answer.
struct AskFormAnswerAction {
    let send: @MainActor (PanelValue, String, MessageID) async -> ReplyFeedback?

    /// Records the answer as this card's submission so the card shows progress and errors.
    @MainActor
    func callAsFunction(_ answers: PanelValue, summary: String, for id: MessageID, reply: AttentionReplyState) {
        Task { await reply.send(summary, for: id) { text, id in await send(answers, text, id) } }
    }
}

extension EnvironmentValues {
    @Entry var askFormAnswer: AskFormAnswerAction?
}
