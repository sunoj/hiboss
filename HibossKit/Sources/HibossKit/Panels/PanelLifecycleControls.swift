// Shared wall filters, placement actions, and durable result acknowledgement.
// Exports PanelWallFilter and PanelLifecycleMenu for macOS and iOS.
// Dependencies: SwiftUI, PanelsModel, and task lifecycle contracts.

import SwiftUI

public struct PanelWallFilter: View {
    @ObservedObject var model: PanelsModel
    public init(model: PanelsModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                picker.pickerStyle(.segmented).fixedSize(horizontal: true, vertical: false)
                picker.pickerStyle(.menu)
            }
            if let error = model.questionnaireError {
                Label(kitL("Questions unavailable"), systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button(kitL("Retry questions")) { Task { await model.refreshPendingQuestionnaires() } }
                    .disabled(model.isLoadingQuestions)
            }
            if let error = model.preferenceError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var picker: some View {
        Picker(kitL("Panels"), selection: $model.section) {
            ForEach(PanelWallSection.allCases) { section in Text(title(section)).tag(section) }
        }
    }

    private func title(_ section: PanelWallSection) -> String {
        switch section {
        case .active: kitL("Active")
        case .needsInput: kitL("Needs input") + " (\(model.pendingQuestionnaireCount))"
        case .results: kitL("Results") + (model.unreadResults > 0 ? " (\(model.unreadResults))" : "")
        case .archived: kitL("Archived")
        }
    }
}

public struct PanelWallEmptyState: View {
    @ObservedObject var model: PanelsModel
    public init(model: PanelsModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.section == .needsInput && model.isLoadingQuestions {
                ProgressView(kitL("Loading questions…"))
            } else {
                Label(title, systemImage: model.section == .needsInput ? "text.bubble" : "rectangle.stack").font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary)
                Button(kitL("Refresh")) { Task { await model.load() } }.disabled(model.isLoading)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var title: String {
        if model.failureMessage != nil { return kitL("Panels unavailable") }
        if model.section == .needsInput {
            return model.questionnaireError == nil ? kitL("No questions waiting") : kitL("Questions unavailable")
        }
        return kitL("No panels here")
    }
    private var message: String {
        if let failure = model.failureMessage { return failure }
        if model.section == .needsInput {
            return model.questionnaireError == nil ? kitL("New questions from your agents appear here.") : kitL("Retry to check for unanswered questions.")
        }
        return kitL("Task progress and results appear here.")
    }
}
public struct PanelLifecycleMenu: View {
    let tile: PanelTile
    @ObservedObject var model: PanelsModel
    public init(tile: PanelTile, model: PanelsModel) { self.tile = tile; self.model = model }
    public var body: some View {
        if tile.metadata != nil {
            Button(tile.preference.placement == .pinned ? "Unpin" : "Pin", systemImage: "pin") {
                Task { await model.setPreference(tile, placement: tile.preference.placement == .pinned ? .automatic : .pinned) }
            }
            Button(tile.preference.placement == .archived ? "Restore" : "Archive", systemImage: "archivebox") {
                Task { await model.setPreference(tile, placement: tile.preference.placement == .archived ? .automatic : .archived) }
            }
            if tile.lifecycle.taskState.isTerminal, tile.preference.acknowledgedTerminalVersion != tile.metadata?.metadataVersion {
                Button("Acknowledge result", systemImage: "checkmark.circle") {
                    Task { await model.setPreference(tile, acknowledge: true) }
                }
            }
        }
    }
}
public struct PanelOutcomeView: View {
    let tile: PanelTile
    public init(tile: PanelTile) { self.tile = tile }
    public var body: some View {
        if let result = tile.lifecycle.result {
            VStack(alignment: .leading, spacing: 6) {
                Label(result.title, systemImage: tile.lifecycle.taskState.symbol).font(.headline)
                if let message = result.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if let date = panelDate(tile.lifecycle.terminalAt) { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
