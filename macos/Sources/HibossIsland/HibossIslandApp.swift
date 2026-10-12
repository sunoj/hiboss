// Application shell wiring settings, SSE flow, menu bar, Dock, and option UI.
// Exports: HibossIslandApp, settings commands, and AppDelegate lifecycle integration.
// Dependencies: SwiftUI, AppKit, Combine, settings, flow, and panel controller.

import AppKit
import HibossKit
import Combine
import SwiftUI

@main
struct HibossIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window(productName, id: "main") {
            MainView(settings: appDelegate.settings, flow: appDelegate.flow,
                notificationNavigation: appDelegate.notificationNavigation,
                joinRequests: appDelegate.joinRequests,
                overviewStore: appDelegate.overview, requiredInputs: appDelegate.requiredInputs,
                identity: appDelegate.identity)
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            AppWindowCommands(navigation: appDelegate.notificationNavigation,
                pairingLinks: appDelegate.pairingLinks)
        }

        Window(L("Settings"), id: "settings") {
            SettingsScene(
                settings: appDelegate.settings,
                flow: appDelegate.flow,
                preferencesStore: appDelegate.preferencesStore,
                notifications: appDelegate.notifications,
                requiredInputs: appDelegate.requiredInputs,
                updater: appDelegate.updater.state,
                launchAtLogin: appDelegate.launchAtLogin,
                pairingLinks: appDelegate.pairingLinks
            )
        }
        .defaultSize(width: 960, height: 640)
    }
}

/// Commands are evaluated at launch whether or not any window is open, so this is where the
/// scene-id opener reaches the status menu and notification routing.
private struct AppWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let navigation: MessageNotificationNavigation
    let pairingLinks: PairingLinkRouter

    var body: some Commands {
        let action = openWindow
        let _ = navigation.install { action(id: "main") }
        let _ = pairingLinks.install { action(id: "settings") }
        CommandGroup(replacing: .appSettings) {
            Button(L("Settings")) {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
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
    let notificationCenter = SystemMessageNotificationCenter()
    let notificationNavigation = MessageNotificationNavigation()
    let pairingLinks = PairingLinkRouter()
    let notifications: MessageNotificationStore
    let joinRequests: JoinRequestsModel
    var joinRequestPolling: Task<Void, Never>?
    private var panelController: IslandPanelController?
    private(set) var statusItem: NSStatusItem?
    var identity: AccountAuthorization { settings.identity }
    let overview: OverviewStore
    let requiredInputs = RequiredInputStore()
    var cancellables: Set<AnyCancellable> = []

    override convenience init() {
        self.init(settings: AppSettings())
    }

    init(settings: AppSettings) {
        self.settings = settings
        notifications = MessageNotificationStore(center: notificationCenter)
        preferencesStore = BossPreferencesStore(api: SettingsPreferencesService(settings: settings))
        joinRequests = JoinRequestsModel {
            (try? settings.connectionConfig().get()).map { HibossAPI(config: $0) }
        }
        overview = OverviewStore(identity: settings.identity)
        super.init()
        overview.bind(flow: flow, inputs: requiredInputs)
        AccountAuthorization.shared.observe { [weak self] _ in
            self?.notifications.disconnect()
            self?.notificationNavigation.target = nil
            self?.notificationNavigation.deviceRequestsFocus = nil
        }.store(in: &cancellables)
    }

    /// Dock click. SwiftUI does not reopen a closed single `Window` scene here, and the Island
    /// panel counts as a visible window, so the main window opens whatever `flag` says.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notificationNavigation.openMainWindow()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["HIBOSS_ATTENTION_PREVIEW"] == nil else { return }
        notificationCenter.onOpen = { [weak self] id in self?.notificationNavigation.open(id) }
        notificationCenter.onOpenJoinRequest = { [weak self] id in
            self?.notificationNavigation.openDeviceRequests(requestID: id)
        }
        notificationCenter.start()
        Task { await notifications.prepareAuthorization() }
        observePresentationPreferences()
        panelController = IslandPanelController(flow: flow, settings: settings, overview: overview)
        observeJoinRequests()
        Task { [weak self] in
            guard let self else { return }
            await settings.loadToken()
            connectIfConfigured()
        }
    }

    /// A clicked hiboss://pair link only opens the redeem sheet; the boss still confirms it.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme?.lowercased() == "hiboss" }) else { return }
        pairingLinks.receive(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    private func connectIfConfigured() {
        if case let .success(config) = settings.connectionConfig() {
            let api = HibossAPI(config: config)
            requiredInputs.connect(api)
            flow.connect(api: api)
            notifications.connect(api: api)
            Task { await preferencesStore.load() }
        }
    }

    private func observePresentationPreferences() {
        settings.$showsInDock
            .removeDuplicates()
            .map { AppSettings.activationPolicy(showsInDock: $0) }
            .sink { NSApp.setActivationPolicy($0) }
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

        overview.$snapshot
            .sink { [weak self] snapshot in
                let count = snapshot.answerability.isLoaded ? snapshot.today.decisions.count : nil
                self?.updateStatusCount(count)
            }
            .store(in: &cancellables)
    }

    func setStatusItemVisible(_ isVisible: Bool) {
        guard isVisible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = L("HiBoss Island")
        statusItem = item
        let snapshot = overview.snapshot
        updateStatusCount(snapshot.answerability.isLoaded ? snapshot.today.decisions.count : nil)
        refreshStatusMenu()
    }

    private func updateStatusCount(_ count: Int?) {
        guard let button = statusItem?.button else { return }
        AppIdentity.configure(button, count: count)
    }

    func refreshStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: flow.connectionState.label, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Reconnect"), action: #selector(reconnect)))
        menu.addItem(menuItem(L("Open HiBoss…"), action: #selector(showMainWindow)))
        menu.addItem(deviceRequestsMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem(L("Quit HiBoss Island"), action: #selector(quit)))
        statusItem.menu = menu
    }

    func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func reconnect() {
        Task { [weak self] in
            guard let self, case let .success(config) = await settings.connect() else { return }
            let api = HibossAPI(config: config)
            requiredInputs.connect(api)
            flow.connect(api: api)
            notifications.connect(api: api)
            await preferencesStore.load()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        requiredInputs.disconnect()
        notifications.disconnect()
    }

    @objc private func showMainWindow() {
        notificationNavigation.openMainWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
