// Presents questionnaire editing, local drafts, deadlines, durable receipts and read-only access.
// Exports the shared native editor for macOS and iOS panel detail surfaces.
// Dependencies: SwiftUI, QuestionnaireModel, native controls, and answer summaries.

import SwiftUI

struct QuestionnaireEditor: View {
    let record: QuestionnaireRecord
    let webModel: PanelWebModel
    let currentTime: @MainActor () -> Date
    let changed: @MainActor () async -> Void
    @StateObject private var model: QuestionnaireModel
    /// Keep the current step across clock ticks, refreshes and draft saves.
    @State private var stepIndex: Int?

    init(
        record: QuestionnaireRecord, bossID: String, answerer: BossIdentity, service: any QuestionnaireServing,
        webModel: PanelWebModel,
         currentTime: @escaping @MainActor () -> Date, changed: @escaping @MainActor () async -> Void) {
        self.record = record
        self.webModel = webModel
        self.currentTime = currentTime
        self.changed = changed
        _model = StateObject(
            wrappedValue: QuestionnaireModel(
                record: record, bossID: bossID, answerer: answerer, service: service, currentTime: currentTime))
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: model.editing.definition.title).font(.headline)
                if let submission = model.latest.submission {
                    QuestionnaireAnswerView(record: model.latest, submission: submission)
                } else {
                    metadata
                    let steps = model.steps
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let now = currentTime()
                        if !model.latest.isOpen(at: now) { closedStatus }
                        fields(at: now, steps: steps)
                    }
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: record) { _, updated in model.update(updated) }
        .onChange(of: model.latest) { _, _ in Task { await changed() } }
        .task { await model.recover() }
    }

    @ViewBuilder private func fields(at now: Date, steps: QuestionnaireSteps?) -> some View {
        let enabled = model.canEdit && model.latest.isOpen(at: now)
        if let steps {
            QuestionnaireStepper(model: model, store: model.store, steps: steps, webModel: webModel,
                                 enabled: enabled, index: $stepIndex) {
                primaryControl(at: now, submit: .review(ready: steps.allRequiredAnswered(state: model.store.state)))
            } status: { onReview in
                if onReview { notices(at: now) } else { status(at: now, submit: .hidden) }
            }
        } else {
            QuestionnaireFields(model: model, store: model.store, webModel: webModel, enabled: enabled)
            status(at: now, submit: .form)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                model.editing.definition.blocking
                    ? kitL("Agent needs your answers to continue") : kitL("Optional feedback"),
                  systemImage: model.editing.definition.blocking ? "text.bubble" : "bubble.left")
            if let deadline = panelDate(model.latest.expiresAt) {
                Text(kitL("Answer by \(deadline.formatted(date: .abbreviated, time: .shortened))"))
            }
            if model.hasSavedDraft { Text(kitL("Draft saved on this device")) }
        }.font(.caption).foregroundStyle(.secondary)
    }

    /// Where the editor's own Submit control goes: after the form, only on the review page, or nowhere.
    private enum SubmitSlot { case form, hidden, review(ready: Bool) }

    /// Notices and the primary control together, below the form or the current step.
    @ViewBuilder private func status(at now: Date, submit: SubmitSlot) -> some View {
        if model.isSending {
            primaryControl(at: now, submit: submit)
            notices(at: now)
        } else {
            notices(at: now)
            primaryControl(at: now, submit: submit)
        }
    }

    /// Submit, or what replaces it while sending or after an unconfirmed submission.
    @ViewBuilder private func primaryControl(at now: Date, submit: SubmitSlot) -> some View {
        if model.isSending {
            #if os(iOS)
            if submitShowsProgress(submit) || model.isRecovering {
                Button {} label: {
                    HStack {
                        Text(model.isRecovering ? kitL("Checking saved answer…") : kitL("Submit answers"))
                        NativeDelayedProgress()
                    }.frame(minHeight: 44)
                }.buttonStyle(.bordered).disabled(true)
            }
            #endif
        } else if model.pendingID != nil {
            Button { Task { await model.recover() } } label: {
                Text(kitL("Check submission")).frame(minHeight: Self.actionHeight)
            }.buttonStyle(.bordered)
        } else if model.latest.isOpen(at: now), !model.hasNewRevision, model.access.readOnlyReason == nil {
            switch submit {
            case .form where !hasSubmitControl: submitButton(ready: true)
            case let .review(ready): submitButton(ready: ready)
            default: EmptyView()
            }
        }
    }

    @ViewBuilder private func notices(at now: Date) -> some View {
        if model.isSending {
            #if os(iOS)
            NativePendingNotice(
                title: kitL("Waiting for the submission receipt…"),
                detail: kitL(
                    "Your answer isn't confirmed. Your draft is saved. Close this panel and check again."
                ),
                retry: { await changed() }
            )
            #else
            ProgressView(model.isRecovering ? kitL("Checking saved answer…") : kitL("Submitting answers…"))
            #endif
        } else if model.pendingID != nil {
            Text(kitL("Submission status is unconfirmed. Check before retrying.")).font(.callout)
        } else if model.hasNewRevision && model.latest.isOpen(at: now) {
            Text(kitL("This questionnaire changed. Your previous draft is preserved.")).font(.callout)
            Button(kitL("Start revised questionnaire")) {
                model.restart()
                stepIndex = model.steps?.initialIndex(state: model.store.state)
            }
        } else if model.latest.isOpen(at: now), let reason = model.access.readOnlyReason {
            Label(reason, systemImage: "eye").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func submitButton(ready: Bool) -> some View {
        Button { Task { await model.submit() } } label: {
            Text(kitL("Submit answers")).frame(minWidth: 72, minHeight: Self.actionHeight)
        }
            #if os(iOS)
            .modifier(ProminentActionModifier(labelColor: Color(uiColor: .systemBackground)))
            #else
            .buttonStyle(.borderedProminent)
            #endif
            .disabled(!model.canEdit || !ready)
            .accessibilityIdentifier("questionnaire-submit")
    }

    /// iOS matches the stepper's 44-point Next; macOS keeps its native control height.
    static var actionHeight: CGFloat? {
        #if os(iOS)
        44
        #else
        nil
        #endif
    }

    private func submitShowsProgress(_ submit: SubmitSlot) -> Bool {
        switch submit {
        case .form: return !hasSubmitControl
        case .review: return true
        case .hidden: return false
        }
    }

    private var hasSubmitControl: Bool {
        model.editing.definition.formSpec.elements.values.contains {
            $0.on?["press"]?.action == "submitRequest"
        }
    }

    private var closedStatus: some View {
        Label(model.latest.state == "expired" || model.latest.state == "open"
              ? kitL("This questionnaire has expired. Your draft is preserved.")
              : model.latest.withdrawalReason ?? kitL("This questionnaire is closed."), systemImage: "lock")
            .font(.callout).foregroundStyle(.secondary)
    }
}

struct QuestionnaireFields: View {
    @ObservedObject var model: QuestionnaireModel
    @ObservedObject var store: PanelStore
    let webModel: PanelWebModel
    let enabled: Bool
    var spec: PanelSpec?
    var elementIDs: [String]?

    var body: some View {
        let spec = spec ?? model.formSpec
        VStack(alignment: .leading, spacing: 14) {
            ForEach(elementIDs ?? [spec.root], id: \.self) { id in
                PanelRenderer(spec: spec, store: store, webModel: webModel, elementID: id)
            }
        }
            #if os(iOS)
            .environment(\.nativeSubmissionPending, model.isSending)
            #endif
            .disabled(!enabled)
            .onChange(of: store.state) { _, _ in model.save() }
    }
}
