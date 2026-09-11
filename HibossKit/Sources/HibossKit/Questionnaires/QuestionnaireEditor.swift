// Presents questionnaire editing, local drafts, deadlines, and durable receipts.
// Exports the shared native editor for macOS and iOS panel detail surfaces.
// Dependencies: SwiftUI, QuestionnaireModel, native controls, and answer summaries.

import SwiftUI

struct QuestionnaireEditor: View {
    let record: QuestionnaireRecord
    let webModel: PanelWebModel
    let now: Date
    let changed: @MainActor () async -> Void
    @StateObject private var model: QuestionnaireModel

    init(record: QuestionnaireRecord, bossID: String, service: any QuestionnaireServing, webModel: PanelWebModel,
         now: Date, currentTime: @escaping @MainActor () -> Date, changed: @escaping @MainActor () async -> Void) {
        self.record = record
        self.webModel = webModel
        self.now = now
        self.changed = changed
        _model = StateObject(wrappedValue: QuestionnaireModel(record: record, bossID: bossID, service: service, currentTime: currentTime))
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.editing.definition.title).font(.headline)
                if let submission = model.latest.submission {
                    QuestionnaireAnswerView(record: model.latest, submission: submission)
                } else {
                    metadata
                    if !model.latest.isOpen(at: now) { closedStatus }
                    QuestionnaireFields(model: model, store: model.store, webModel: webModel,
                        enabled: model.canEdit && model.latest.isOpen(at: now))
                    status
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

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(model.editing.definition.blocking ? kitL("Agent needs your answers to continue") : kitL("Optional feedback"),
                  systemImage: model.editing.definition.blocking ? "text.bubble" : "bubble.left")
            if let deadline = panelDate(model.latest.expiresAt) {
                Text(kitL("Answer by") + " " + deadline.formatted(date: .abbreviated, time: .shortened))
            }
            if model.hasSavedDraft { Text(kitL("Draft saved on this device")) }
        }.font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var status: some View {
        if model.isSending {
            ProgressView(model.isRecovering ? kitL("Checking saved answer…") : kitL("Submitting answers…"))
        } else if model.pendingID != nil {
            Text(kitL("Submission status is unconfirmed. Check before retrying.")).font(.callout)
            Button(kitL("Check submission")) { Task { await model.recover() } }
        } else if model.hasNewRevision && model.latest.isOpen(at: now) {
            Text(kitL("This questionnaire changed. Your previous draft is preserved.")).font(.callout)
            Button(kitL("Start revised questionnaire")) { model.restart() }
        } else if model.latest.isOpen(at: now) {
            if !model.editing.definition.formSpec.elements.values.contains(where: { $0.on?["press"]?.action == "submitRequest" }) {
                Button(kitL("Submit answers")) { Task { await model.submit() } }
                    .buttonStyle(.borderedProminent).disabled(!model.canEdit)
            }
        }
    }

    private var closedStatus: some View {
        Label(model.latest.state == "expired" || model.latest.state == "open"
              ? kitL("This questionnaire has expired. Your draft is preserved.")
              : model.latest.withdrawalReason ?? kitL("This questionnaire is closed."), systemImage: "lock")
            .font(.callout).foregroundStyle(.secondary)
    }
}

private struct QuestionnaireFields: View {
    @ObservedObject var model: QuestionnaireModel
    @ObservedObject var store: PanelStore
    let webModel: PanelWebModel
    let enabled: Bool

    var body: some View {
        PanelRenderer(spec: model.editing.definition.formSpec, store: store, webModel: webModel)
            .disabled(!enabled)
            .onChange(of: store.state) { _, _ in model.save() }
    }
}
