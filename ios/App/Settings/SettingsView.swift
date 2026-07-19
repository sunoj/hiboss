// Settings tab: connection details, notification note, and sign-out.
// Exports: SettingsView bound to the ConnectionStore.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import HibossKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var connection: ConnectionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.hbLargeTitle)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("CONNECTION") {
                        row(label: "Server", value: connection.config?.serverURL.host() ?? "—")
                        divider
                        row(label: "Status", value: connection.isConfigured ? "Connected" : "Not connected",
                            valueColor: connection.isConfigured ? Theme.positive : Theme.ink3)
                    }

                    section("NOTIFICATIONS") {
                        row(label: "Push", value: "Set up in a later build", valueColor: Theme.ink3)
                    }

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
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper.ignoresSafeArea())
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).hbLabel().foregroundStyle(Theme.ink4).padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        }
    }

    private func row(label: String, value: String, valueColor: Color = Theme.ink2) -> some View {
        HStack {
            Text(label).font(.hbBody).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).font(.hbCallout).foregroundStyle(valueColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
    }
}
