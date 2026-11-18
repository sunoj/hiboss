// Shared step-by-step questionnaire flow with a final review page that owns submission.
// Exports QuestionnaireStepper; the step index lives in the caller so refreshes never move it.
// Dependencies: SwiftUI, QuestionnaireSteps, QuestionnaireFields and the shared PanelRenderer.

import SwiftUI

struct QuestionnaireStepper<Action: View, Status: View>: View {
    @ObservedObject var model: QuestionnaireModel
    @ObservedObject var store: PanelStore
    let steps: QuestionnaireSteps
    let webModel: PanelWebModel
    let enabled: Bool
    @Binding var index: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The review page's trailing control (Submit, or what replaces it while sending or recovering).
    @ViewBuilder let reviewAction: () -> Action
    @ViewBuilder let status: (_ onReview: Bool) -> Status

    private var count: Int { steps.steps.count }
    private var current: Int { min(max(index ?? steps.initialIndex(state: store.state), 0), count) }

    private var headerID: QuestionnaireHeaderID { QuestionnaireHeaderID(model: ObjectIdentifier(model)) }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 14) {
                header.id(headerID)
                Group {
                    if current < count { stepBody } else { review }
                }.id(current)
                navigation
                status(current == count)
            }
            .onAppear { if index == nil { index = steps.initialIndex(state: store.state) } }
            .onChange(of: index) { previous, next in
                // Opening on the first question keeps the panel's own header in view.
                if previous == nil && next == 0 { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        proxy.scrollTo(headerID, anchor: .top)
                    }
                }
            }
        }
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
        .frame(maxWidth: .infinity, minHeight: QuestionnaireEditor.actionHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var navigation: some View {
        HStack {
            Button { index = current - 1 } label: {
                Label(kitL("Back"), systemImage: "chevron.left")
                    .frame(minHeight: QuestionnaireEditor.actionHeight)
            }
            .buttonStyle(.bordered).disabled(current == 0)
            .accessibilityIdentifier("questionnaire-back")
            Spacer()
            if current == count {
                reviewAction()
            } else {
                Button { index = current + 1 } label: {
                    Text(current == count - 1 ? kitL("Review") : kitL("Next"))
                        .frame(minWidth: 72, minHeight: QuestionnaireEditor.actionHeight)
                }
                #if os(iOS)
                .modifier(ProminentActionModifier(labelColor: Color(uiColor: .systemBackground)))
                #else
                .buttonStyle(.borderedProminent)
                #endif
                .disabled(enabled && !steps.isComplete(inStep: current, state: store.state))
                .accessibilityIdentifier("questionnaire-next")
            }
        }
    }
}

/// Scroll target for one questionnaire's step header inside the host's scroll view.
private struct QuestionnaireHeaderID: Hashable { let model: ObjectIdentifier }
