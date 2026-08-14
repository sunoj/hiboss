// Presentation pane for local option-surface preferences.
// Exports: PresentationSettingsPane.
// Dependencies: SwiftUI, AppSettings, and SoundPlaying.

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
            } header: {
                Text(L("Alerts"))
            } footer: {
                Text(L("Fallback sound for alerts without a priority rule."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
