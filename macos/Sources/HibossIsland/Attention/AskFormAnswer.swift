// Sends a form ask's structured answer from any card without threading it through every view.
// Exports: AskFormAnswerAction and EnvironmentValues.askFormAnswer, set once by MainView.
// Dependencies: SwiftUI, HibossKit PanelValue/MessageID, and AttentionReplyState.

import HibossKit
import SwiftUI

/// `(answers, summary, id)`; nil means the server accepted the answer.
struct AskFormAnswerAction {
    let send: @MainActor (PanelValue, String, MessageID) async -> ReplyFeedback?

    /// Records the answer as this card's submission so the card shows progress and errors;
    /// true when the server accepted it.
    @MainActor
    func callAsFunction(_ answers: PanelValue, summary: String, for id: MessageID,
                        reply: AttentionReplyState) async -> Bool {
        await reply.send(summary, for: id) { text, id in await send(answers, text, id) }
        return reply.errors[id] == nil
    }
}

extension EnvironmentValues {
    @Entry var askFormAnswer: AskFormAnswerAction?
    /// Set by a sheet that should close once its form ask has been answered.
    @Entry var askFormDidAnswer: (() -> Void)?
}
