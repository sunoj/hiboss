// Phone permission and registration are distinct, with local recovery actions and delayed progress.
// Exports: SettingsPermissionSection, embedded by SettingsNotificationsView.
// Dependencies: SwiftUI, PushStatusStore, PushManager, SettingsWaitView, Theme.

import SwiftUI

struct SettingsPermissionSection: View {
    @ObservedObject var push: PushStatusStore
    @ObservedObject private var manager = PushManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Section("This phone") {
            LabeledContent("Notifications") { Text(verbatim: push.label) }
            if push.isEnabled {
                deviceStatus
                Button("Notification settings") { push.openSystemSettings() }
            } else {
                Button {
                    if push.mustOpenSystemSettings { push.openSystemSettings() } else { push.request() }
                } label: {
                    if push.mustOpenSystemSettings {
                        Text("Open Settings to Enable")
                    } else {
                        Text("Enable Notifications")
                    }
                }
                .disabled(push.isRequesting || !push.hasLoaded)
            }
            if push.isRequesting {
                SettingsWaitView(title: "Waiting for notification permission…", actionTitle: "Check again") {
                    Task { await push.refresh() }
                }
            }
            if let failure = push.failureMessage {
                Label { Text(verbatim: failure) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(Theme.negative)
            }
        }
    }

    @ViewBuilder
    private var deviceStatus: some View {
        switch manager.registration {
        case .idle:
            Text("Not registered").foregroundStyle(Theme.ink2)
            retryRegistration
        case .registering:
            SettingsWaitView(title: "Registering this phone…", actionTitle: "Go Back") { dismiss() }
        case .registered:
            Label("Registered", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.positive)
        case let .failed(message):
            Label { Text(verbatim: message) } icon: { Image(systemName: "exclamationmark.triangle") }
                .foregroundStyle(Theme.negative)
            retryRegistration
        }
    }

    private var retryRegistration: some View {
        Button("Register this phone") { Task { await manager.registerIfAuthorized() } }
    }
}
