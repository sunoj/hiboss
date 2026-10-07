// Device entry points and the existing registered-device inventory in a native Form.
// Exports: SettingsDevicesView. Security actions remain in their original models and views.
// Dependencies: SwiftUI, HibossKit BossClientsSection, ConnectionStore, JoinRequestsModel.

import HibossKit
import SwiftUI

struct SettingsDevicesView: View {
    @ObservedObject var connection: ConnectionStore
    @ObservedObject var joinRequests: JoinRequestsModel

    var body: some View {
        Form {
            if connection.config != nil || isDemoMode {
                Section {
                    NavigationLink {
                        PairDeviceView(config: connection.config)
                    } label: {
                        Label("Pair another device", systemImage: "qrcode")
                    }
                    NavigationLink {
                        MacSigninView(config: connection.config, api: connection.makeAPI())
                    } label: {
                        Label("Sign in a Mac", systemImage: "laptopcomputer.and.iphone")
                    }
                    NavigationLink {
                        DeviceRequestsView(model: joinRequests)
                    } label: {
                        Label("Device Requests", systemImage: "desktopcomputer.and.arrow.down")
                    }
                    .badge(joinRequests.pendingCount)
                }
            }
            if let api = connection.makeAPI(), let config = connection.config {
                BossClientsSection(api: api, kind: .ios, deviceLabel: connection.deviceLabel) { token in
                    try connection.activateDeviceToken(token, replacing: config)
                }
                .id(connection.config?.bossToken)
            }
            if connection.config == nil, !isDemoMode {
                Section { Text("Connect to a server before pairing another device.") }
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
    }
}
