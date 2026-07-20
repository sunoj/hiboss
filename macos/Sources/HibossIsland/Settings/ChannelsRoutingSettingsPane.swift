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
        SettingsPaneBody(pane: .routing) {
            SettingsNotAppliedNotice()
            VStack(spacing: 0) {
                headerRow
                ForEach(SettingsPreferencesLogic.priorities, id: \.self) { priority in
                    routingRow(priority)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.notice))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.notice)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            tableHeader("PRIORITY", width: 124, alignment: .leading)
            ForEach(SettingsPreferencesLogic.channels, id: \.self) { channel in
                tableHeader(channel.settingsLabel, width: 86, alignment: .center)
            }
            tableHeader("Sound", width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func routingRow(_ priority: MessagePriority) -> some View {
        HStack(spacing: 0) {
            priorityLabel(priority)
                .frame(width: 124, alignment: .leading)
            ForEach(SettingsPreferencesLogic.channels, id: \.self) { channel in
                RoutingToggle(isOn: channelIsOn(priority: priority, channel: channel)) {
                    toggle(priority: priority, channel: channel)
                }
                .frame(width: 86)
            }
            Picker("", selection: soundBinding(for: priority)) {
                ForEach(OptionSound.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
        }
    }

    private func tableHeader(
        _ label: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(label)
            .font(Font.caption.monospaced())
            .tracking(0.7)
            .foregroundStyle(Color.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func priorityLabel(_ priority: MessagePriority) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priority.settingsColor)
                .frame(width: 8, height: 8)
            Text(priority.settingsLabel)
                .font(Font.caption.monospaced())
                .tracking(0.7)
                .foregroundStyle(Color.secondary)
        }
    }

    private func channelIsOn(priority: MessagePriority, channel: NotificationChannel) -> Bool {
        let routing = SettingsPreferencesLogic.routing(from: preferencesStore.preferences)
        return Set(routing[priority] ?? []).contains(channel)
    }

    private func toggle(priority: MessagePriority, channel: NotificationChannel) {
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

    private func soundBinding(for priority: MessagePriority) -> Binding<OptionSound> {
        Binding {
            settings.sound(for: priority)
        } set: { sound in
            settings.setSound(sound, for: priority)
            soundPlayer.play(sound)
        }
    }
}
