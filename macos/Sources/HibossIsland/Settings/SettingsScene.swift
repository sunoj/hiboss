// Native macOS Settings shell with sidebar navigation and save footer.
// Exports: SettingsScene.
// Dependencies: SwiftUI, AppSettings, OptionFlowStore, and settings panes.

import HibossKit
import SwiftUI

struct SettingsScene: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var preferencesStore: BossPreferencesStore
    @ObservedObject var updater: UpdaterState
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    let soundPlayer: any SoundPlaying

    @State private var selection: SettingsPane = .connection
    @State private var statusMessage = ""
    @State private var isConnecting = false

    init(
        settings: AppSettings,
        flow: OptionFlowStore,
        preferencesStore: BossPreferencesStore,
        updater: UpdaterState = UpdaterState(),
        launchAtLogin: LaunchAtLoginController = LaunchAtLoginController(),
        soundPlayer: any SoundPlaying = SystemSoundPlayer()
    ) {
        self.settings = settings
        self.flow = flow
        self.preferencesStore = preferencesStore
        self.updater = updater
        self.launchAtLogin = launchAtLogin
        self.soundPlayer = soundPlayer
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(210)
        } detail: {
            detailPane
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .frame(minWidth: 820, minHeight: 560)
        .task { await loadPreferencesIfConfigured() }
    }

    private var sidebar: some View {
        List(SettingsPane.allCases, selection: $selection) { pane in
            Label(pane.title, systemImage: pane.icon)
                .tag(pane)
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch SettingsPreferencesLogic.selectedPane(selection) {
        case .general:
            GeneralSettingsPane(launchAtLogin: launchAtLogin)
        case .connection:
            ConnectionSettingsPane(
                settings: settings,
                flow: flow,
                statusMessage: statusMessage,
                isConnecting: isConnecting,
                reconnect: connect
            )
        case .notifications:
            NotificationsSettingsPane(settings: settings, preferencesStore: preferencesStore)
        case .routing:
            ChannelsRoutingSettingsPane(
                settings: settings,
                preferencesStore: preferencesStore,
                soundPlayer: soundPlayer
            )
        case .quietHours:
            QuietHoursSettingsPane(preferencesStore: preferencesStore)
        case .presentation:
            PresentationSettingsPane(settings: settings, soundPlayer: soundPlayer)
        case .systemDoctor:
            SystemDoctorSettingsPane(
                settings: settings,
                flow: flow,
                preferencesStore: preferencesStore
            )
        case .about:
            AboutSettingsPane(updater: updater)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            SettingsFooterStatus(
                text: L("Listening"),
                isActive: flow.connectionState == .connected,
                error: footerError
            )
            Spacer()
            Button(L("Save & Connect"), action: connect)
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var isBusy: Bool {
        if isConnecting { return true }
        if preferencesStore.state == .loading || preferencesStore.state == .saving { return true }
        return false
    }

    private var footerError: String? {
        if let validation = SettingsPreferencesLogic.validationMessage(for: preferencesStore.preferences) {
            return validation
        }
        if case let .failed(message) = preferencesStore.state {
            return message
        }
        return statusMessage.isEmpty ? nil : statusMessage
    }

    private func connect() {
        Task { await saveAndConnect() }
    }

    private func loadPreferencesIfConfigured() async {
        guard settings.isConfigured, preferencesStore.state == .idle else { return }
        await preferencesStore.load()
    }

    private func saveAndConnect() async {
        if let validation = SettingsPreferencesLogic.validationMessage(for: preferencesStore.preferences) {
            statusMessage = validation
            return
        }
        switch settings.save() {
        case let .failure(error):
            statusMessage = error.localizedDescription
        case let .success(config):
            await connect(using: config)
        }
    }

    private func connect(using config: ConnectionConfig) async {
        isConnecting = true
        statusMessage = L("Checking connection...")
        let api = HibossAPI(config: config)
        do {
            try await api.verifyConnection()
            flow.connect(api: api)
            await preferencesStore.save()
            statusMessage = preferencesStore.state == .loaded ? "" : statusMessage
        } catch {
            statusMessage = error.localizedDescription
        }
        isConnecting = false
    }
}
