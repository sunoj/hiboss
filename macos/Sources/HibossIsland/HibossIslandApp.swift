// Application shell wiring settings, SSE flow, menu bar, Dock, and option UI.
// Exports: HibossIslandApp and AppDelegate lifecycle integration.
// Dependencies: SwiftUI, AppKit, Combine, settings, flow, and panel controller.

import AppKit
import Combine
import SwiftUI

@main
struct HibossIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(
            "HiBoss Island",
            systemImage: "capsule.tophalf.filled",
            isInserted: statusItemBinding
        ) {
            MenuContent(
                settings: appDelegate.settings,
                flow: appDelegate.flow,
                showSettings: appDelegate.showSettings
            )
        }
    }

    private var statusItemBinding: Binding<Bool> {
        Binding(
            get: { appDelegate.isStatusItemInserted },
            set: { appDelegate.isStatusItemInserted = $0 }
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings: AppSettings
    let flow = OptionFlowStore()
    @Published var isStatusItemInserted: Bool
    private var panelController: IslandPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        let settings = AppSettings()
        self.settings = settings
        isStatusItemInserted = settings.showsStatusItem
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observePresentationPreferences()
        panelController = IslandPanelController(flow: flow, settings: settings)
        settingsWindowController = SettingsWindowController(settings: settings, flow: flow)
        if case let .success(config) = settings.connectionConfig() {
            flow.connect(api: HibossAPI(config: config))
        } else {
            presentSettingsWhenReady()
        }
    }

    func showSettings() {
        settingsWindowController?.present()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { showSettings() }
        return true
    }

    private func observePresentationPreferences() {
        settings.$showsStatusItem
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.isStatusItemInserted = isVisible
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settings.$presentationMode.removeDuplicates(),
            settings.$showsStatusItem.removeDuplicates()
        )
        .sink { mode, showsStatusItem in
            let needsDock = mode == .window || !showsStatusItem
            NSApp.setActivationPolicy(needsDock ? .regular : .accessory)
        }
        .store(in: &cancellables)
    }

    private func presentSettingsWhenReady() {
        DispatchQueue.main.async { [weak self] in
            self?.showSettings()
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var flow: OptionFlowStore
    let showSettings: () -> Void

    var body: some View {
        Label(flow.connectionState.label, systemImage: statusIcon)
        Divider()
        Button("Reconnect") { reconnect() }
            .disabled(!settings.isConfigured)
        Button("Settings…", action: showSettings)
        Divider()
        Button("Quit HiBoss Island") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusIcon: String {
        flow.connectionState == .connected ? "dot.radiowaves.left.and.right" : "circle.dotted"
    }

    private func reconnect() {
        guard case let .success(config) = settings.connectionConfig() else { return }
        flow.connect(api: HibossAPI(config: config))
    }
}
