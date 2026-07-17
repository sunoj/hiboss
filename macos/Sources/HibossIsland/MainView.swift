// Provides the HiBoss main window with message history and app settings.
// Exports: MainView and SettingsPaneView for native window scenes.
// Dependencies: SwiftUI, AppSettings, HibossAPI, and OptionFlowStore.

import SwiftUI

struct MainView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore

    var body: some View {
        TabView {
            HistoryView(flow: flow)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsPaneView(settings: settings, flow: flow)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct HistoryView: View {
    @ObservedObject var flow: OptionFlowStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            historyContent
        }
        .task {
            if flow.historyState == .idle { await flow.refreshHistory() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Messages").font(.title2.bold())
                Text("Recent agent and boss messages").foregroundStyle(.secondary)
            }
            Spacer()
            connectionIndicator
            Button {
                Task { await flow.refreshHistory() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh messages")
            .disabled(flow.historyState == .loading)
        }
        .padding(20)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(flow.connectionState == .connected ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(flow.connectionState.label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if flow.historyMessages.isEmpty, flow.historyState == .loading {
            ProgressView("Loading messages…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if flow.historyMessages.isEmpty {
            ContentUnavailableView(
                "No Messages",
                systemImage: "tray",
                description: Text(historyEmptyDescription)
            )
        } else {
            List(flow.historyMessages) { message in
                HistoryRow(message: message)
            }
            .listStyle(.inset)
        }
    }

    private var historyEmptyDescription: String {
        if case let .failed(message) = flow.historyState { return message }
        return "Agent messages will appear here."
    }
}

private struct HistoryRow: View {
    let message: HistoryMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sender).font(.headline)
                Spacer()
                Text(message.status.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(message.body).textSelection(.enabled).lineLimit(5)
            if !message.options.isEmpty {
                Text(message.options.joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Text(directionLabel)
                if message.priority != "normal" { Text(message.priority.uppercased()) }
                Spacer()
                Text(message.createdAt)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    private var sender: String {
        message.direction == "boss_to_agent" ? "You" : message.agentName ?? "Agent"
    }

    private var directionLabel: String {
        message.direction == "boss_to_agent" ? "Sent to agent" : "From agent"
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
