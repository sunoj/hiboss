// Polls pending join requests while connected and surfaces them in the menu bar and notifications.
// Exports: AppDelegate join-request wiring (polling lifecycle, notifications, status menu item).
// Dependencies: AppKit, Combine, HibossKit JoinRequestsModel, and JoinRequestNotifier.

import AppKit
import Combine
import HibossKit

extension AppDelegate {
    /// Polls every 30 s only while the live stream is connected; a 403 ends polling until reconnect.
    func observeJoinRequests() {
        let notifier = JoinRequestNotifier(center: notificationCenter) { [notifications] in
            await notifications.prepareAuthorization()
            return notifications.authorization == .authorized || notifications.authorization == .provisional
        }
        joinRequests.onNewRequests = { requests in
            Task { await notifier.announce(requests) }
        }
        flow.$connectionState
            .map { $0 == .connected }
            .removeDuplicates()
            .sink { [weak self] isConnected in self?.setJoinRequestPolling(isConnected) }
            .store(in: &cancellables)
        Publishers.CombineLatest(joinRequests.$requests, joinRequests.$state)
            .map { requests, _ in requests.count }
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshStatusMenu() }
            .store(in: &cancellables)
    }

    func deviceRequestsMenuItem() -> NSMenuItem {
        let count = joinRequests.pendingCount
        let item = menuItem(L("Device Requests"), action: #selector(showDeviceRequests))
        item.badge = count > 0 ? NSMenuItemBadge(count: count) : nil
        return item
    }

    private func setJoinRequestPolling(_ isConnected: Bool) {
        joinRequestPolling?.cancel()
        joinRequestPolling = isConnected ? Task { [joinRequests] in await joinRequests.poll() } : nil
    }

    @objc private func showDeviceRequests() {
        notificationNavigation.openDeviceRequests()
    }
}
