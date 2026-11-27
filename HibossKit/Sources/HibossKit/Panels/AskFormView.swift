// The answer surface of a form ask on iOS and macOS: the v2 control plus one Submit button.
// Exports: AskFormView; the caller sends `answers` and the readable summary as the reply.
// Dependencies: SwiftUI, AskForm, PanelRankedChoice, and PanelItemReview.

import SwiftUI

public struct AskFormView: View {
    let form: AskForm
    let isSubmitting: Bool
    /// True when the server accepted the answer; false keeps the form and its draft.
    let onSubmit: (_ answers: PanelValue, _ summary: String) async -> Bool
    /// Runs after the "Answer sent" confirmation has been shown, e.g. to close a sheet.
    var onAnswered: (() -> Void)?
    @State private var value: PanelValue = .null
    @State private var sent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(form: AskForm, isSubmitting: Bool,
                onSubmit: @escaping (_ answers: PanelValue, _ summary: String) async -> Bool,
                onAnswered: (() -> Void)? = nil) {
        self.form = form
        self.isSubmitting = isSubmitting
        self.onSubmit = onSubmit
        self.onAnswered = onAnswered
    }

    public var body: some View {
        Group {
            if sent { confirmation.transition(.scale(scale: 0.85).combined(with: .opacity)) } else { editor }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: sent)
    }

    private var confirmation: some View {
        Label(kitL("Answer sent"), systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: sent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .accessibilityIdentifier("ask-form-sent")
    }

    private func submit() {
        let answers = form.answer(from: value)
        let summary = form.summary(value)
        Task {
            guard await onSubmit(answers, summary) else { return }
            sent = true
            try? await Task.sleep(for: .milliseconds(1200))
            onAnswered?()
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            control
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().controlSize(.small) }
                    Text(isSubmitting ? kitL("Sending…") : kitL("Submit answer"))
                }
            }
            .buttonStyle(AskFormSubmitStyle())
            .disabled(isSubmitting || !form.isComplete(value))
            .accessibilityIdentifier("ask-form-submit")
            if !isSubmitting, !form.isComplete(value), form.fitsSizeLimit(form.answer(from: value)) {
                Text(kitL("Answer every item to submit."))
                    .font(.caption).foregroundStyle(.secondary)
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

/// A full-width primary action: accent fill when it can be pressed, a quiet but readable fill
/// when it cannot, never a small grey bar.
private struct AskFormSubmitStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AskFormSubmitLabel(configuration: configuration)
    }
}

private struct AskFormSubmitLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isEnabled ? Color.accentColor : Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
