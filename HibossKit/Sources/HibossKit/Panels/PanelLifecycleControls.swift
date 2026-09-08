// Shared wall filters, placement actions, and durable result acknowledgement.
// Exports PanelWallFilter and PanelLifecycleMenu for macOS and iOS.
// Dependencies: SwiftUI, PanelsModel, and task lifecycle contracts.

import SwiftUI

public struct PanelWallFilter: View {
    @ObservedObject var model: PanelsModel
    public init(model: PanelsModel) { self.model = model }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Panels", selection: $model.section) {
                ForEach(PanelWallSection.allCases) { section in
                    Text(section == .results && model.unreadResults > 0 ? "Results (\(model.unreadResults))" : section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            if let error = model.preferenceError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
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
