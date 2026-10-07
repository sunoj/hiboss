// Preference load/save feedback and a reachable save action shared by notification pages.
// Exports: PreferencesFeedbackSection, PreferencesSaveButton; both preserve the existing draft.
// Dependencies: SwiftUI, HibossKit, PreferencesStore, SettingsWaitView, Theme.

import HibossKit
import SwiftUI

struct PreferencesFeedbackSection: View {
    @ObservedObject var store: PreferencesStore
    let api: HibossAPI?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Section {
            if store.isSaving {
                EmptyView()
            } else if store.state == .loading || store.state == .idle {
                SettingsWaitView(title: "Loading preferences…", actionTitle: "Go Back") { dismiss() }
            } else if case let .failed(message) = store.state {
                Label("Changes couldn’t be saved or loaded", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.negative)
                Text(verbatim: message).foregroundStyle(Theme.ink2)
                if store.hasLoaded { Text("Your changes are still here.") }
                Button("Try again") {
                    Task {
                        if store.isDirty { await store.save() } else { await store.load(api: api) }
                    }
                }
                .accessibilityIdentifier("settings-preferences-retry")
            } else if store.state == .unavailable {
                Text("Connect to a server to change notification preferences.")
            } else if store.isDirty {
                Text("Unsaved changes").foregroundStyle(Theme.ink2)
            } else if store.didSave {
                Label("Changes saved", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.positive)
                    .accessibilityIdentifier("settings-preferences-saved")
            }
        }
    }
}

struct PreferencesSaveButton: View {
    @ObservedObject var store: PreferencesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if store.isDirty || store.isSaving {
            VStack(spacing: 12) {
                if store.isSaving {
                    SettingsWaitView(title: "Saving changes…", actionTitle: "Go Back", showsContext: false) {
                        dismiss()
                    }
                }
                Button("Save Changes") { Task { await store.save() } }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("settings-preferences-save")
            }
            .padding()
            .background(Theme.paper)
        }
    }
}
