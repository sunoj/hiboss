// One notification overview: permission, current delivery rules, timing, privacy and decision alerts.
// Exports: SettingsNotificationsView and SettingsDeliveryView using the same preference draft.
// Dependencies: SwiftUI, HibossKit, SettingsPermissionSection, PreferencesFeedbackSection, Theme.

import HibossKit
import SwiftUI

struct SettingsNotificationsView: View {
    @ObservedObject var store: PreferencesStore
    @ObservedObject var push: PushStatusStore
    let api: HibossAPI?
    let onDecisionAlertsChanged: (Bool) -> Void

    var body: some View {
        Form {
            SettingsPermissionSection(push: push)
            if store.hasLoaded {
                deliverySummary
                QuietHoursSection(store: store)
                decisionSection
                privacySection
                Section {
                    NavigationLink("Delivery details") { SettingsDeliveryView(store: store, api: api) }
                        .accessibilityIdentifier("settings-delivery")
                } footer: {
                    Text("Change phone alerts and delivery to other channels by priority.")
                }
            }
            PreferencesFeedbackSection(store: store, api: api)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { PreferencesSaveButton(store: store) }
    }

    private var deliverySummary: some View {
        Section {
            LabeledContent("Phone alerts") {
                Text(verbatim: store.enabledPriorities)
                    .foregroundStyle(Theme.ink2)
            }
        } header: {
            Text("When you’ll hear from HiBoss")
        } footer: {
            if !push.isEnabled { Text("Enable notifications above to receive phone alerts.") }
        }
    }

    private var decisionSection: some View {
        Section {
            Toggle("Alert on decisions", isOn: Binding(
                get: { store.decisionAlerts },
                set: {
                    store.setDecisionAlerts($0)
                    onDecisionAlertsChanged($0)
                }
            ))
        } footer: {
            Text("Decisions can alert at normal priority, including on the lock screen and Dynamic Island.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Private Notifications", isOn: Binding(
                get: { store.privatePush }, set: { store.setPrivatePush($0) }
            ))
            .accessibilityIdentifier("settings-private-notifications")
        } footer: {
            Text("Show a generic alert. Message content loads from your server when you open HiBoss.")
        }
    }
}

struct SettingsDeliveryView: View {
    @ObservedObject var store: PreferencesStore
    let api: HibossAPI?

    var body: some View {
        Form {
            PushTieringSection(store: store)
            RoutingSection(store: store)
            PreferencesFeedbackSection(store: store, api: api)
        }
        .navigationTitle("Delivery details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { PreferencesSaveButton(store: store) }
    }
}

extension PreferencesStore {
    var enabledPriorities: String {
        let priorities: [HibossKit.MessagePriority] = [.critical, .high, .normal, .low]
        let enabled = priorities.filter { pushRule(for: $0).deliver }.map(\.localizedTitle)
        return enabled.isEmpty ? String(localized: "Off") : enabled.formatted(.list(type: .and))
    }
}
