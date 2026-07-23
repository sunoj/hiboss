// Settings tab: connection, notifications, boss routing prefs, and sign-out.
// Exports: SettingsView bound to the ConnectionStore.
// Dependencies: SwiftUI, HibossKit, Push/Preferences stores, theme tokens.

import HibossKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var connection: ConnectionStore
    @StateObject private var push = PushStatusStore()
    @StateObject private var prefs = PreferencesStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.hbLargeTitle)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    connectionSection
                    NotificationsSection(push: push)
                    if prefs.state != .unavailable {
                        RoutingSection(store: prefs)
                        QuietHoursSection(store: prefs)
                        preferencesStatus
                    }
                    if prefs.isDirty { saveButton }
                    signOutButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
        .task {
            await push.refresh()
            if isDemoMode { prefs.loadDemo() } else { await prefs.load(api: connection.makeAPI()) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await push.refresh() } }
        }
    }

    private var connectionSection: some View {
        SettingsSection(title: "CONNECTION") {
            SettingsRow(label: "Server", value: connection.config?.serverURL.host() ?? "—")
            SettingsDivider()
            SettingsRow(
                label: "Status",
                value: connection.isConfigured ? "Connected" : "Not connected",
                valueColor: connection.isConfigured ? Theme.positive : Theme.ink3
            )
        }
    }

    @ViewBuilder
    private var preferencesStatus: some View {
        switch prefs.state {
        case .loading:
            statusNote("Loading preferences…", color: Theme.ink3)
        case let .failed(message):
            statusNote(message, color: Theme.negative)
        default:
            EmptyView()
        }
    }

    private func statusNote(_ text: String, color: Color) -> some View {
        Text(text).font(.hbFootnote).foregroundStyle(color).padding(.leading, 6)
    }

    private var saveButton: some View {
        Button { Task { await prefs.save() } } label: {
            HStack(spacing: 8) {
                if prefs.isSaving { ProgressView().controlSize(.small) }
                Text(prefs.isSaving ? "Saving…" : "Save changes")
                    .font(.hbBody).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.positive)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(prefs.isSaving)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            connection.signOut()
        } label: {
            Text("Sign Out")
                .font(.hbBody)
                .foregroundStyle(Theme.negative)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct NotificationsSection: View {
    @ObservedObject var push: PushStatusStore

    var body: some View {
        SettingsSection(title: "NOTIFICATIONS") {
            HStack {
                Text("Push").font(.hbBody).foregroundStyle(Theme.ink)
                Spacer()
                Text(push.label)
                    .font(.hbCallout)
                    .foregroundStyle(push.isEnabled ? Theme.positive : Theme.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if !push.isEnabled {
                SettingsDivider()
                Button(action: action) {
                    Text(actionTitle)
                        .font(.hbCallout).foregroundStyle(Theme.positive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionTitle: String {
        push.mustOpenSystemSettings ? "Open Settings to enable" : "Enable notifications"
    }

    private func action() {
        if push.mustOpenSystemSettings { push.openSystemSettings() } else { push.request() }
    }
}
