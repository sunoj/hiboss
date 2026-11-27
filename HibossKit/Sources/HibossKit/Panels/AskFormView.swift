// The answer surface of a form ask on iOS and macOS: the v2 control plus one Submit button.
// Exports: AskFormView; the caller sends `answers` and the readable summary as the reply.
// Dependencies: SwiftUI, AskForm, PanelRankedChoice, and PanelItemReview.

import SwiftUI

public struct AskFormView: View {
    let form: AskForm
    let isSubmitting: Bool
    let onSubmit: (_ answers: PanelValue, _ summary: String) -> Void
    @State private var value: PanelValue = .null

    public init(form: AskForm, isSubmitting: Bool,
                onSubmit: @escaping (_ answers: PanelValue, _ summary: String) -> Void) {
        self.form = form
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            control
            HStack(spacing: 10) {
                Button {
                    onSubmit(form.answer(from: value), form.summary(value))
                } label: {
                    Text(kitL("Submit answer")).frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || !form.isComplete(value))
                .accessibilityIdentifier("ask-form-submit")
                if isSubmitting { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            if !form.fitsSizeLimit(form.answer(from: value)) {
                Text(kitL("Shorten the notes to send this answer."))
                    .font(.caption).foregroundStyle(.red)
            }
            Text(kitL("The agent receives this as input. It does not approve any action."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch form.kind {
        case .rankedChoice:
            PanelRankedChoice(label: form.label, options: form.options, topK: form.topK, value: $value,
                confirmsOrder: false)
        case .itemReview:
            PanelItemReview(label: form.label, items: form.items, verdicts: form.verdicts, value: $value)
        }
    }
}
