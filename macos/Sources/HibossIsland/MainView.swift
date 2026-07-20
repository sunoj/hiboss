// Provides the HiBoss main window with message history and app settings.
// Exports: MainView and SettingsPaneView for native window scenes.
// Dependencies: SwiftUI, AppSettings, HibossAPI, and OptionFlowStore.

import SwiftUI
import HibossKit

struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore

    var body: some View {
        HistoryView(flow: flow)
            .frame(minWidth: 760, minHeight: 520)
    }
}

struct SettingsPaneView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    /// Previews the pick — choosing a sound you cannot hear is choosing blind.
    let soundPlayer: any SoundPlaying
    @State private var statusMessage = ""
    @State private var isConnecting = false

    init(
        settings: AppSettings,
        flow: OptionFlowStore,
        soundPlayer: any SoundPlaying = SystemSoundPlayer()
    ) {
        self.settings = settings
        self.flow = flow
        self.soundPlayer = soundPlayer
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Server URL", text: $settings.serverAddress)
                SecureField("Boss Token", text: $settings.bossToken)
            }
            Section("Presentation") {
                Picker("Option display", selection: $settings.presentationMode) {
                    ForEach(OptionPresentationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Show menu bar icon", isOn: $settings.showsStatusItem)
            }
            Section("Alert") {
                Toggle("Play a sound for new questions", isOn: $settings.playsSound)
                Picker("Sound", selection: $settings.alertSound) {
                    ForEach(OptionSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                .disabled(!settings.playsSound)
                .onChange(of: settings.alertSound) { soundPlayer.play(settings.alertSound) }
            }
            Section {
                HStack {
                    Text(statusMessage.isEmpty ? flow.connectionState.label : statusMessage)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save & Connect") { connect() }.disabled(isConnecting)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func connect() {
        switch settings.save() {
        case let .failure(error): statusMessage = error.localizedDescription
        case let .success(config): connect(using: config)
        }
    }

    private func connect(using config: ConnectionConfig) {
        isConnecting = true
        statusMessage = "Checking connection…"
        Task {
            let api = HibossAPI(config: config)
            do {
                try await api.verifyConnection()
                flow.connect(api: api)
                statusMessage = "Listening for messages"
            } catch {
                statusMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
