// Application shell wiring settings, SSE flow, menu bar, Dock, and option UI.
// Exports: HibossIslandApp and AppDelegate lifecycle integration.
// Dependencies: SwiftUI, AppKit, Combine, settings, flow, and panel controller.

import AppKit
import HibossKit
import Combine
import SwiftUI

@main
struct HibossIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("HiBoss", id: "main") {
            MainView(settings: appDelegate.settings, flow: appDelegate.flow)
        }
        .defaultSize(width: 960, height: 640)

        Settings {
            SettingsScene(
                settings: appDelegate.settings,
                flow: appDelegate.flow,
                preferencesStore: appDelegate.preferencesStore,
                updater: appDelegate.updater.state,
                launchAtLogin: appDelegate.launchAtLogin
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings: AppSettings
    let preferencesStore: BossPreferencesStore
    let flow = OptionFlowStore()
    let updater = SparkleUpdater()
    let launchAtLogin = LaunchAtLoginController()
    private var panelController: IslandPanelController?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        let settings = AppSettings()
        self.settings = settings
        preferencesStore = BossPreferencesStore(api: SettingsPreferencesService(settings: settings))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observePresentationPreferences()
        panelController = IslandPanelController(flow: flow, settings: settings)
        Task { [weak self] in
            guard let self else { return }
            await settings.loadToken()
            connectIfConfigured()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    private func connectIfConfigured() {
        if case let .success(config) = settings.connectionConfig() {
            flow.connect(api: HibossAPI(config: config, clientSource: "macos"))
            Task { await preferencesStore.load() }
        }
    }

    private func observePresentationPreferences() {
        Publishers.CombineLatest(
            settings.$presentationMode.removeDuplicates(),
            settings.$showsStatusItem.removeDuplicates()
        )
        .sink { mode, showsStatusItem in
            let needsDock = mode == .window || !showsStatusItem
            NSApp.setActivationPolicy(needsDock ? .regular : .accessory)
        }
        .store(in: &cancellables)

        settings.$showsStatusItem
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.setStatusItemVisible(isVisible)
            }
            .store(in: &cancellables)

        flow.$connectionState
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshStatusMenu() }
            .store(in: &cancellables)
    }

    private func setStatusItemVisible(_ isVisible: Bool) {
        guard isVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.tophalf.filled",
            accessibilityDescription: L("HiBoss Island")
        )
        item.button?.toolTip = L("HiBoss Island")
        statusItem = item
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: flow.connectionState.label, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Reconnect"), action: #selector(reconnect)))
        menu.addItem(menuItem(L("Open HiBoss…"), action: #selector(showMainWindow)))
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Quit HiBoss Island"), action: #selector(quit)))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func reconnect() {
        guard case let .success(config) = settings.connectionConfig() else { return }
        flow.connect(api: HibossAPI(config: config))
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "HiBoss" })?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
