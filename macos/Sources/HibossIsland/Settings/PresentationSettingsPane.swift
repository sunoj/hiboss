// Presentation pane for local option-surface preferences.
// Exports: PresentationSettingsPane.
// Dependencies: SwiftUI, AppSettings, SoundPlaying, and DesignTokens.

import SwiftUI

struct PresentationSettingsPane: View {
    @ObservedObject var settings: AppSettings
    let soundPlayer: any SoundPlaying

    var body: some View {
        SettingsPaneBody(pane: .presentation) {
            SettingsSection(title: "Alerts") {
                SettingsRow(title: "Play sounds", caption: "Play an alert when a new question appears.") {
                    Toggle("", isOn: $settings.playsSound)
                        .labelsHidden()
                }
                LastSettingsRow(title: "Default sound", caption: "Fallback sound for alerts without a priority rule.") {
                    Picker("", selection: $settings.alertSound) {
                        ForEach(OptionSound.allCases) { sound in
                            Text(sound.label).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .disabled(!settings.playsSound)
                    .onChange(of: settings.alertSound) { soundPlayer.play($1) }
                }
            }
        }
    }
}
