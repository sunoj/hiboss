// Asks closed elsewhere: apply a resolution push and retract stale delivered notifications.
// Exports: InboxStore.current, applyResolution and reconcileDeliveredNotifications.
// Dependencies: HibossKit MessageID, DeliveredAskNotifications.

import Foundation
import HibossKit

@MainActor
extension InboxStore {
    /// The started store a background resolution push marks; weak so a rebuilt session drops it.
    static weak var current: InboxStore?

    /// Removes a closed ask from the open list, including from a snapshot fetch in flight.
    func applyResolution(_ id: MessageID) {
        requiredInputs.removeAll { $0.id == id }
        if requiredInputRefreshing {
            requiredFetchResolutions.insert(id)
            requiredFetchUpdates.removeValue(forKey: id)
        }
    }

    /// After a required-input read, retracts notifications of asks that are no longer open,
    /// covering resolution pushes the system throttled or dropped.
    /// A demo's open list says nothing about the real account's notifications.
    func reconcileDeliveredNotifications(readAt: Date) async {
        guard !isDemoMode else { return }
        let open = Set(requiredInputs.map(\.id.rawValue))
        let closed = Set(history.filter { $0.status == "replied" || $0.status == "expired" }.map(\.id.rawValue))
        let identifiers = DeliveredAskNotifications.closedIdentifiers(
            in: await deliveredNotifications.delivered(), open: open, closed: closed, readAt: readAt
        )
        if !identifiers.isEmpty { deliveredNotifications.remove(identifiers: identifiers) }
    }
}
