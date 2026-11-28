// Presentation pane for local option-surface preferences.
// Exports: PresentationSettingsPane.
// Dependencies: SwiftUI, HibossKit MessagePriority, AppSettings, and SoundPlaying.

import HibossKit
import SwiftUI

struct PresentationSettingsPane: View {
    @ObservedObject var settings: AppSettings
    let soundPlayer: any SoundPlaying

    var body: some View {
        Form {
            Section {
                Toggle(L("Play sounds"), isOn: $settings.playsSound)
                Picker(L("Default sound"), selection: $settings.alertSound) {
                    ForEach(OptionSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                .disabled(!settings.playsSound)
                .onChange(of: settings.alertSound) { soundPlayer.play($1) }
                // One sound per priority; these were beside the removed channel matrix.
                ForEach(MessagePriority.allCases, id: \.self) { priority in
                    Picker(priority.localizedTitle, selection: soundBinding(for: priority)) {
                        ForEach(OptionSound.allCases) { sound in
                            Text(sound.label).tag(sound)
                        }
                    }
                    .disabled(!settings.playsSound)
                    .accessibilityIdentifier("settings.sound.\(priority.rawValue)")
                }
            } header: {
                Text(L("Alerts"))
            } footer: {
                Text(L("Fallback sound for alerts without a priority rule."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
