// Shows durable questionnaires inside the shared panel detail experience.
// Exports PanelQuestionnairesView for iOS and macOS, with explicit draft restart/recovery.
// Dependencies: SwiftUI, PanelsModel, native PanelRenderer, and questionnaire models.

import SwiftUI

public struct PanelQuestionnairesView: View {
    let tile: PanelTile
    @ObservedObject var panels: PanelsModel
    @State private var records: [QuestionnaireRecord] = []
    @State private var service: (any QuestionnaireServing)?
    @State private var error: String?
    @State private var isRefreshing = false
    @State private var hasLoaded = false
    @State private var refreshGeneration = 0

    public init(tile: PanelTile, panels: PanelsModel) { self.tile = tile; self.panels = panels }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !panels.isDemoMode && isRefreshing && error == nil {
                #if os(iOS)
                NativePendingNotice(title: kitL("Loading questions…"), retry: retry)
                #else
                if !hasLoaded { ProgressView(kitL("Loading questions…")) }
                #endif
            }
            if let error {
                Label(kitL("Questions unavailable"), systemImage: "wifi.exclamationmark").foregroundStyle(
                    .orange)
                Text(verbatim: error).foregroundStyle(.secondary).font(.callout)
                Button(kitL("Retry questions")) { Task { await refresh() } }.disabled(isRefreshing)
            }
            if let service, let bossID = tile.metadata?.targetBossId {
                ForEach(records) { record in
                    QuestionnaireEditor(
                        record: record, bossID: bossID, service: service, webModel: panels.webModel,
                        currentTime: { panels.serverNow(for: tile.id) }) {
                            await panels.refreshPendingQuestionnaires()
                        }
                        .id("\(service.questionnaireScope)/\(bossID)/\(record.id)")
                }
            }
        }
        .task(id: tile.id) {
            guard !panels.isDemoMode else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }

    private func refresh(replacing: Bool = false) async {
        guard !isRefreshing || replacing else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        defer { if generation == refreshGeneration { isRefreshing = false } }
        do {
            let api = try await panels.questionnaireService()
            let fetched = try await api.fetchQuestionnaires(panelID: tile.id)
            try Task.checkCancellation()
            guard generation == refreshGeneration else { return }
            records = fetched.sorted { $0.isOpen(at: panels.now) && !$1.isOpen(at: panels.now) }
            service = api
            error = nil
            hasLoaded = true
        } catch is CancellationError { return }
        catch {
            guard generation == refreshGeneration else { return }
            if (error as? HibossAPIError)?.isAuthFailure == true { records = []; service = nil }
            self.error = error.localizedDescription
        }
    }

    #if os(iOS)
    private func retry() async {
        await refresh(replacing: true)
    }
    #endif
}
