// iOS one-question-per-page questionnaire flow with a final review page that owns submission.
// Exports QuestionnaireStepper; the step index lives in the caller so refreshes never move it.
// Dependencies: SwiftUI, QuestionnaireSteps, QuestionnaireFields and the shared PanelRenderer.

#if os(iOS)
import SwiftUI

struct QuestionnaireStepper<Status: View>: View {
    @ObservedObject var model: QuestionnaireModel
    @ObservedObject var store: PanelStore
    let steps: QuestionnaireSteps
    let webModel: PanelWebModel
    let enabled: Bool
    @Binding var index: Int?
    @ViewBuilder let status: (_ onReview: Bool) -> Status

    private var count: Int { steps.steps.count }
    private var current: Int { min(max(index ?? steps.initialIndex(state: store.state), 0), count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Group {
                if current < count { stepBody } else { review }
            }.id(current)
            navigation
            status(current == count)
        }
        .onAppear { if index == nil { index = steps.initialIndex(state: store.state) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(current < count ? kitL("Question \(current + 1) of \(count)") : kitL("Review your answers"))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier("questionnaire-step-counter")
            ProgressView(value: Double(min(current + 1, count)), total: Double(count))
                .accessibilityHidden(true)
        }
    }

    private var stepBody: some View {
        let ids = (current == 0 ? steps.intro : []) + steps.steps[current].elementIDs
        return VStack(alignment: .leading, spacing: 8) {
            QuestionnaireFields(model: model, store: store, webModel: webModel, enabled: enabled,
                                spec: steps.spec, elementIDs: ids)
            if enabled && !steps.isComplete(inStep: current, state: store.state) {
                Text(kitL("Answer this question to continue.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps.reviewRows(state: store.state)) { row in
                Button { index = row.step } label: { reviewRow(row) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("questionnaire-review-\(row.step)")
                Divider()
            }
        }
    }

    private func reviewRow(_ row: QuestionnaireReviewRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.label).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let value = row.value {
                    Text(verbatim: value).font(.callout).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(kitL("Not answered")).font(.callout)
                        .foregroundStyle(row.required ? Color.orange : Color.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var navigation: some View {
        HStack {
            Button { index = current - 1 } label: {
                Label(kitL("Back"), systemImage: "chevron.left").frame(minHeight: 44)
            }
            .buttonStyle(.bordered).disabled(current == 0)
            .accessibilityIdentifier("questionnaire-back")
            Spacer()
            if current < count {
                Button { index = current + 1 } label: {
                    Text(current == count - 1 ? kitL("Review") : kitL("Next")).frame(minWidth: 72, minHeight: 44)
                }
                .modifier(ProminentActionModifier(labelColor: Color(uiColor: .systemBackground)))
                .disabled(enabled && !steps.isComplete(inStep: current, state: store.state))
                .accessibilityIdentifier("questionnaire-next")
            }
        }
    }
}
#endif
