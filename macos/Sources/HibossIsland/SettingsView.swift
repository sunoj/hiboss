// Provides connection and presentation configuration for the macOS client.
// Exports: SettingsView used by the SwiftUI Settings scene.
// Dependencies: SwiftUI, AppSettings, HibossAPI, and OptionFlowStore.

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    @State private var statusMessage = ""
    @State private var isConnecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("HiBoss Island")
                    .font(.system(size: 24, weight: .bold))
                Text("Show agent choices at the top of your screen.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Server URL").font(.headline)
                TextField("https://hiboss.example.com", text: $settings.serverAddress)
                    .textFieldStyle(.roundedBorder)
                Text("Boss Token").font(.headline)
                SecureField("hb_boss_…", text: $settings.bossToken)
                    .textFieldStyle(.roundedBorder)
            }
            presentationSettings
            HStack {
                Circle()
                    .fill(flow.connectionState == .connected ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(statusMessage.isEmpty ? flow.connectionState.label : statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save & Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConnecting)
            }
        }
        .padding(24)
        .frame(width: 440, height: 390)
    }

    private var presentationSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presentation").font(.headline)
            Picker("Option display", selection: $settings.presentationMode) {
                ForEach(OptionPresentationMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Show menu bar icon", isOn: $settings.showsStatusItem)
        }
    }

    private func connect() {
        switch settings.save() {
        case let .failure(error):
            statusMessage = error.localizedDescription
        case let .success(config):
            isConnecting = true
            statusMessage = "Checking connection…"
            Task {
                let api = HibossAPI(config: config)
                do {
                    try await api.verifyConnection()
                    flow.connect(api: api)
                    statusMessage = "Listening for option messages"
                } catch {
                    statusMessage = error.localizedDescription
                }
                isConnecting = false
            }
        }
    }
}
