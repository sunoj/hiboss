// Device management pane alongside Connection in native macOS Settings.
// Exports: DevicesSettingsPane.
// Dependencies: SwiftUI, AppSettings, and HibossKit's shared device section.

import HibossKit
import SwiftUI

struct DevicesSettingsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            if let config = settings.activeClientConfig {
                BossClientsSection(api: HibossAPI(config: config))
                    .id(config.serverURL.absoluteString + config.bossToken)
            } else {
                Section { Text(L("Connect to manage devices.")).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}
