// Channels and routing pane for server-backed priority delivery.
// Exports: ChannelsRoutingSettingsPane.
// Dependencies: SwiftUI, HibossKit preferences, AppSettings sounds, and DesignTokens.

import HibossKit
import SwiftUI

struct ChannelsRoutingSettingsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var preferencesStore: BossPreferencesStore
    let soundPlayer: any SoundPlaying

    var body: some View {
        Form {
            Section {
                RoutingMatrix(
                    preferencesStore: preferencesStore,
                    settings: settings,
                    soundPlayer: soundPlayer
                )
            } header: {
                Text(L("Routing"))
            } footer: {
                SettingsNotAppliedNotice()
            }
        }
        .formStyle(.grouped)
    }
}

/// Priority × channel checkbox grid with per-priority client-side alert sounds.
private struct RoutingMatrix: View {
    @ObservedObject var preferencesStore: BossPreferencesStore
    @ObservedObject var settings: AppSettings
    let soundPlayer: any SoundPlaying

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            GridRow {
                Text(L("Priority"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(SettingsPreferencesLogic.channels, id: \.self) { channel in
                    Text(channel.settingsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.center)
                }
                Text(L("Sound"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
            }

            ForEach(SettingsPreferencesLogic.priorities, id: \.self) { priority in
                GridRow {
                    priorityLabel(priority)
                    ForEach(SettingsPreferencesLogic.channels, id: \.self) { channel in
                        Toggle(channel.settingsLabel, isOn: channelBinding(priority: priority, channel: channel))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .gridColumnAlignment(.center)
                            .accessibilityLabel(L("\(priority.settingsLabel) via \(channel.settingsLabel)"))
                    }
                    Picker(L("Sound"), selection: soundBinding(for: priority)) {
                        ForEach(OptionSound.allCases) { sound in
                            Text(sound.label).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 120)
                    .gridColumnAlignment(.trailing)
                    .accessibilityLabel(L("\(priority.settingsLabel) sound"))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func priorityLabel(_ priority: MessagePriority) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(priority.settingsColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(priority.settingsLabel)
                .font(.body)
        }
    }

    private func channelBinding(
        priority: MessagePriority,
        channel: NotificationChannel
    ) -> Binding<Bool> {
        Binding {
            let routing = SettingsPreferencesLogic.routing(from: preferencesStore.preferences)
            return Set(routing[priority] ?? []).contains(channel)
        } set: { _ in
            let routing = SettingsPreferencesLogic.routing(from: preferencesStore.preferences)
            let next = SettingsPreferencesLogic.toggledRouting(
                routing,
                priority: priority,
                channel: channel
            )
            preferencesStore.preferences = SettingsPreferencesLogic.preferences(
                preferencesStore.preferences,
                byUpdating: next
            )
        }
    }

    private func soundBinding(for priority: MessagePriority) -> Binding<OptionSound> {
        Binding {
            settings.sound(for: priority)
        } set: { sound in
            settings.setSound(sound, for: priority)
            soundPlayer.play(sound)
        }
    }
}
